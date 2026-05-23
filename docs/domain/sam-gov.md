# SAM.gov Opportunities API

> **Purpose:** How the SAM.gov Opportunities API actually behaves in production — not what the docs say it does. Read this before writing any code that calls SAM.
>
> **Audience:** Contractkit contributors; anyone integrating SAM.gov directly.

Related: [[usaspending]], [[cross-referencing]], [[agency-normalization]], [[naics-and-setasides]]

---

## What this API is (and isn't)

SAM.gov is the federal government's system of record for **active contract opportunities** — presolicitations, solicitations, sources-sought notices, and award notices. The Opportunities API is the read interface to that catalogue.

It is **not** the entity registration API (that's a different system covering UEI/CAGE/SAM-registered vendors). The opportunities and entity APIs share a domain but not a data model. Conflating them is the #1 onboarding mistake.

- **Base URL:** `https://api.sam.gov/opportunities/v2/search`
- **Older v1 endpoint exists but is deprecated** — do not use.
- **Sandbox:** `https://api-alpha.sam.gov/opportunities/v2/search` (separate API key, eventually-consistent with prod).

## Endpoints worth knowing

| Endpoint | Useful? | Notes |
|---|---|---|
| `GET /opportunities/v2/search` | **Yes — the workhorse.** | Listing + filter + pagination. 95% of the gem's SAM traffic. |
| `GET /opportunities/v2/{noticeId}` | Sometimes | Same data as search returns; only useful if you have a noticeId and no other context. |
| `GET /opportunities/v1/*` | No | Deprecated. Different field names. Don't touch. |
| Entity Management API | No (out of scope) | Different base path, different key scope. |

## Authentication

- Single query-string API key: `?api_key=...`.
- Keys are issued via [api.data.gov](https://api.data.gov/signup/) (data.gov is the proxy; SAM is one of many endpoints behind it).
- **Keys do not have a hard 90-day expiry by default**, but **inactive keys are reaped** and federal-tier keys must be re-attested periodically.

> ⚠️ FILL IN: Confirm the exact key-rotation policy you've observed in production. CLAUDE.md infrastructure context mentions a SAM_GOV_API_KEY in AWS Parameter Store — note here when it was last rotated and what triggered the rotation.

### Two tiers

- **Public (non-federal):** ~1,000 requests/day. Default tier for `gem install` users.
- **Federal:** ~10,000 requests/day. Requires a `.gov` / `.mil` email and a different signup flow.

The gem should not assume which tier the user has. Surface a `RateLimitError` with whatever `Retry-After` header was returned and let the consumer decide.

## Rate limits — documented vs real

| Limit | Documented | Observed |
|---|---|---|
| Daily quota | 1,000 / 10,000 | Holds, but resets on UTC midnight not local. |
| Per-minute | not documented | **~20/min sustained** before 429s start. Bursts of 30-40 are fine; sustained higher rates throttle. |
| Concurrent connections | not documented | No hard limit observed, but 5+ parallel requests against the same key noticeably degrade latency. |

> ⚠️ FILL IN: Numbers above come from prior Python-pipeline observations. Re-verify against the current Rails implementation and update.

**Implication for the gem:** default to ≤20 req/min with simple token-bucket pacing. Make it configurable but don't ship a more permissive default.

## Pagination

Offset/limit. The relevant params:

- `limit` — page size; max **1000** (yes, really; most callers cap themselves much lower).
- `offset` — zero-based row index of the first record in the page.
- Response includes `totalRecords` so you can compute total pages.

**Quirks:**
- Offsets near the tail (`offset > 9000`) get noticeably slower.
- Sorting is unstable across pages — if you paginate over a window where records are being updated, you can see duplicates across pages and missed records.
- `postedFrom` + `postedTo` are inclusive on both ends.

**Recommended pattern:** for bulk pulls, paginate by narrow date windows (e.g. day-by-day) rather than one massive query. Avoids the deep-offset slowdown and bounds duplicate exposure.

## Response structure

Top level:

```json
{
  "totalRecords": 3847,
  "limit": 100,
  "offset": 0,
  "opportunitiesData": [ { ...notice... }, ... ],
  "links": [ {"rel": "self", "href": "..."}, {"rel": "next", "href": "..."} ]
}
```

Each notice is a deeply-nested object. The fields below are the ones the gem normalizes.

## Field dictionary — the 20 that matter

| SAM field | Gem field | Type | Notes |
|---|---|---|---|
| `noticeId` | `notice_id` | string | UUID. Stable across updates to the same notice. |
| `title` | `title` | string | Free-text. Frequently truncated/abbreviated. |
| `solicitationNumber` | `solicitation_number` | string \| nil | Format varies wildly by agency. Not a reliable cross-system key. |
| `fullParentPathName` | `agency.full_path` | string | Hierarchy: `DEPT OF DEFENSE.DEPT OF THE AIR FORCE.AFMC.AFLCMC` |
| `fullParentPathCode` | `agency.code_path` | string | Same shape, FPDS agency codes. |
| `department` / `subTier` / `office` | `agency.*` | string | Pre-split components. Don't trust these to match `fullParentPathName` exactly. |
| `postedDate` | `posted_at` | DateTime | ISO 8601 with timezone. Reliable. |
| `responseDeadLine` | `response_deadline_at` | DateTime \| nil | ISO 8601. **Note typo** in upstream field name (`DeadLine` not `Deadline`). |
| `archiveDate` | `archive_at` | Date \| nil | Date only. |
| `type` | `notice_type` | string | See "Notice types" below. |
| `baseType` | `notice_base_type` | string | Coarser grouping than `type`. |
| `naicsCode` | `naics_code` | string | 6-digit string. Sometimes returned as integer; normalize to zero-padded string. |
| `classificationCode` | `psc_code` | string | PSC. 4-char alphanumeric. |
| `typeOfSetAside` | `set_aside_code` | string \| nil | Cryptic abbreviation. See [[naics-and-setasides]]. |
| `typeOfSetAsideDescription` | `set_aside_label` | string \| nil | Human-readable. Sometimes blank when code is set. |
| `placeOfPerformance` | `place_of_performance` | hash | **See data-quality issue below.** |
| `pointOfContact` | `contacts` | array | Always an array, sometimes empty. Email/phone may be missing. |
| `description` | `description` | string \| nil | Plain text or HTML. Can be very long. |
| `additionalInfoLink` | `additional_info_url` | string \| nil | External link. |
| `links` | `links` | array | HATEOAS — `self`, `next`, sometimes `attachments`. |
| `resourceLinks` | `attachments` | array | Direct attachment URLs. May 404. |
| `awardee` / `award` | `award.*` | hash \| nil | Populated only on award notices. |

## Notice types and lifecycle

Notice `type` values you'll see, roughly in lifecycle order:

1. `Special Notice` — informational. Can appear at any stage.
2. `Sources Sought` — market research. No bidding yet.
3. `Presolicitation` — "we plan to solicit." Anchor for capture work.
4. `Combined Synopsis/Solicitation` — small-purchase combined doc.
5. `Solicitation` — the RFP/RFQ. Bidding window opens.
6. `Modification/Amendment` — solicitation changes. **Same `solicitationNumber`** as parent; different `noticeId`.
7. `Award Notice` — contract awarded. `awardee` populated.
8. `Justification` — sole-source / limited-competition justification.
9. `Intent to Bundle Requirements (DoD- Funded)` — DoD-specific.

**Important:** these are loosely sequential, not strictly. A single procurement can skip steps, restart, or fork into multiple solicitations. Do not model "lifecycle" as a state machine; treat each notice as independent and group by `solicitationNumber` where present.

## Known data-quality issues

### `placeOfPerformance.state` polymorphism
Sometimes:
```json
"state": "VA"
```
Sometimes:
```json
"state": { "code": "VA", "name": "Virginia" }
```
The gem must accept both shapes and normalize to a consistent string. Same applies (less frequently) to `country` and `city`.

### Agency name inconsistency
The same agency can appear under different names in `fullParentPathName` vs `department`/`subTier` vs USASpending's own naming. See [[agency-normalization]].

### Solicitation number formats
No standard. Real examples:
- `FA8771-26-R-0042` (Air Force pattern)
- `36C24E26Q0001` (VA pattern)
- `W912DY26R0003` (Army Corps)
- `Notice ID 1234567` (free-text fallback)
- Sometimes blank even on `Solicitation` type notices.

**Implication:** matching across SAM and USASpending by solicitation number works ~30-40% of the time. Don't rely on it as the primary join. See [[cross-referencing]].

### `naicsCode` as integer
Occasionally returned as a JSON number rather than a string. Strips leading zeros. Normalize to a 6-character zero-padded string on ingest.

### Timezone drift in `postedDate`
Almost always `America/New_York` regardless of header claims. Treat any incoming timestamp as ET unless the offset disagrees, then trust the offset.

> ⚠️ FILL IN: Add any other quirks you've hit in production but I haven't covered. Add date observed + source (specific notice ID is helpful for repro).

## Set-aside codes

See [[naics-and-setasides]] for the full table. The short version: codes are 2-7 character abbreviations (`SBA`, `8A`, `HZC`, `SDVOSBC`, `WOSB`), the API returns both code and description, and the gem normalizes both.

## Useful query patterns

- **Last-N-days for daily pipeline:** `postedFrom=MM/dd/yyyy&postedTo=MM/dd/yyyy` (note the US date format — yes, really).
- **By NAICS:** `ncode=541512`. Single value only — to OR across NAICS, run separate queries.
- **By set-aside:** `typeOfSetAside=SBA`. Same single-value constraint.
- **By state of performance:** `state=VA`. Two-letter code.
- **By agency:** `deptname=Department of Veterans Affairs`. **Case-sensitive**, must match exactly — see [[agency-normalization]] for why this is painful.

## Open questions for the maintainer

> ⚠️ FILL IN: Has SAM.gov rolled out the v3 API yet? If so, when does v2 sunset and what's the migration cost for the gem?
>
> ⚠️ FILL IN: What's the current observed daily-quota ceiling on your federal-tier key? Has it shifted since 2025?
>
> ⚠️ FILL IN: Any attachments endpoint behavior changes after the 2026 SAM redesign? (Attachments URLs were unreliable in late 2025.)
