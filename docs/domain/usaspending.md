# USASpending.gov API

> **Purpose:** How the USASpending.gov API behaves in production. Companion to [[sam-gov]] — together they cover the gem's two data sources.
>
> **Audience:** Contractkit contributors; anyone querying federal award data directly.

Related: [[sam-gov]], [[cross-referencing]], [[agency-normalization]]

---

## What this API is

USASpending.gov is Treasury's public-facing system for **historical federal spending** — every contract award, grant, loan, and direct payment the government has executed. The API is the read interface, run by the Bureau of the Fiscal Service.

Unlike SAM, **no authentication is required** and there is no per-key rate quota. There is, however, real throttling at the edge and real timeout behavior on large queries.

- **Base URL:** `https://api.usaspending.gov/api/v2/`
- All endpoints are JSON-only.
- Most search endpoints are **POST** with a JSON `filters` body (not GET — common gotcha).

## Endpoints worth knowing

| Endpoint | Method | Useful? | Notes |
|---|---|---|---|
| `/search/spending_by_award/` | POST | **Yes — primary.** | Filtered award listing. The gem's main read endpoint. |
| `/awards/{generated_unique_award_id}/` | GET | Yes | Single-award detail; richer than the search response. |
| `/awards/funding/` | POST | Sometimes | Award-level funding breakdown (Treasury accounts). |
| `/recipient/duns/{uei}/` | GET | Yes | Recipient lookup by UEI (legacy path; still works). |
| `/recipient/` | POST | Yes | Recipient listing / search. |
| `/agency/` | GET | Sometimes | Reference data; mostly redundant with the FPDS agency tables. |
| `/references/naics/` | GET | Useful for seed data | One-time pull to seed the gem's NAICS lookup. |
| `/bulk_download/` | POST | No | Async; out of scope for v1. |

## Authentication

None. Just send the request. Be polite with a `User-Agent`.

## Rate limits

- **No documented quota.**
- Observed: ~10-15 req/sec sustained against `/search/spending_by_award/` before latency climbs sharply.
- 503s appear under heavy concurrent load (10+ parallel) but are infrequent.
- The edge layer (CloudFront, near as anyone can tell) caches identical GETs aggressively. Repeated single-award lookups are cheap.

**Implication for the gem:** USASpending tolerates more aggressive concurrency than SAM. Default ≤5 req/sec to be conservative; expose a knob.

## Pagination

Page-based (not offset):

```json
{
  "filters": { ... },
  "fields":  [ ... ],
  "page":    1,
  "limit":   100,
  "sort":    "Action Date",
  "order":   "desc"
}
```

- `limit` max is **100** (not 1000). Going higher silently caps.
- `page` is 1-indexed.
- Response includes `page_metadata` with `hasNext`, `total`, `page`, `last_page`.

**Quirks:**
- Past `page=1000` (~100k records) the endpoint can time out before responding. Window large queries by fiscal year or agency to stay shallower.
- Sort key strings are case-sensitive **and space-sensitive** — `"Action Date"` works, `"action_date"` doesn't.

## Awards vs Transactions

This is the single most important conceptual distinction in USASpending.

- An **award** is the contract / grant as a single logical entity, identified by a `generated_unique_award_id` (formerly `PIID`-based).
- A **transaction** is a single modification to that award — the initial obligation, plus every option exercise, deobligation, or admin amendment thereafter.

A 5-year IDIQ can have dozens of transactions across its life. The `/search/spending_by_award/` endpoint returns **awards** with the *aggregated* monetary fields. Transaction-level data requires either `/awards/{id}/` (drilled down per award) or `/search/spending_by_transaction/` (different endpoint, different shape).

**The gem's `Award` model represents an award, not a transaction.** If transaction-level fidelity matters to the consumer (rare), they can use `.raw` and re-fetch.

## Money fields — what they mean

This trips everyone up. Three different "amounts," all useful, all different:

| Field | Meaning |
|---|---|
| `Award Amount` / `total_obligation` | Money obligated to date. Sum of all transactions. **This is what most people want.** |
| `Total Outlays` | Money actually disbursed (cash out the door). Lags obligation by months to years. |
| `Base + All Options Value` / `base_and_all_options_value` | Ceiling — what the contract could be worth if every option is exercised. |
| `Base + Exercised Options Value` | Ceiling so far — base + options that have been exercised. |
| `current_total_value_of_award` | Same as obligated; alias kept for historical reasons. |

**Implication for the gem:** `Award#obligated_amount` returns the obligated value as a `BigDecimal`. Other ceiling fields are exposed but namespaced (`Award#ceiling`, `Award#ceiling_exercised`) so users don't accidentally compare obligation to ceiling.

## Field dictionary — the 20 that matter

| USASpending field | Gem field | Type | Notes |
|---|---|---|---|
| `generated_unique_award_id` | `award_id` | string | Stable across API versions. Use this, not `piid`. |
| `Award ID` / `piid` | `piid` | string | The procurement instrument identifier (contract number). |
| `parent_award_piid` | `parent_piid` | string \| nil | For IDIQ task orders. |
| `Award Type` | `award_type` | string | `"Definitive Contract"`, `"BPA Call"`, `"Delivery Order"`, etc. |
| `Award Amount` | `obligated_amount` | BigDecimal | See money fields above. |
| `Base + All Options Value` | `ceiling` | BigDecimal | |
| `Recipient Name` | `recipient.name` | string | Often shouty caps. |
| `recipient_id` / `uei` | `recipient.uei` | string | 12-char alphanumeric. Replaced DUNS in 2022. |
| `recipient_duns` | `recipient.duns` | string \| nil | Legacy. Still present on pre-2022 awards. |
| `Awarding Agency` | `awarding_agency.name` | string | Top-tier; see [[agency-normalization]]. |
| `Awarding Sub Agency` | `awarding_subagency.name` | string \| nil | E.g. "Air Force" under "DoD". |
| `Funding Agency` | `funding_agency.name` | string | Sometimes differs from awarding. |
| `naics_code` | `naics_code` | string | 6 digits, zero-padded. |
| `psc_code` | `psc_code` | string | 4-char alphanumeric. |
| `Start Date` | `period.start_date` | Date | Period of performance start. |
| `End Date` | `period.end_date` | Date | Period of performance end. Includes options. |
| `Last Modified Date` | `last_modified_at` | DateTime | When USASpending last refreshed this record. |
| `Place of Performance State` | `place_of_performance.state` | string | 2-letter code. |
| `Description` | `description` | string \| nil | Free-text contract description. |
| `Type of Set Aside` | `set_aside_code` | string \| nil | Same code system as SAM. See [[naics-and-setasides]]. |

> ⚠️ FILL IN: Is `Total Outlays` exposed in the gem's `Award` model, or is that v2+ scope? Resolve and document the decision.

## Fiscal year conventions

- Federal fiscal year = **October 1 (prior calendar year) through September 30**. FY2026 ran Oct 1 2025 → Sep 30 2026.
- USASpending filters that take fiscal year (e.g. `"time_period": [{"start_date": "2025-10-01", "end_date": "2026-09-30"}]`) expect calendar dates, not FY integers. Same trap as the SAM date format inversion.
- `Action Date` (the date money was obligated) is what fiscal-year filters key on, not award start date.

## Recipient UEI vs DUNS

- DUNS deprecated April 2022. Records before that have DUNS; records after have UEI.
- The migration was not perfectly clean — some entities have both, some have neither legible, some have UEIs that don't match SAM's UEI for the same entity.
- The gem treats UEI as primary; DUNS is exposed but soft-deprecated.

## Reliability quirks

- **Timeouts on wide queries.** `spending_by_award/` with no time bound and a generic NAICS can take >30s. The gem's default timeout is 30s; bulk callers should narrow filters or use date windowing.
- **`fields` parameter is mandatory** on `/search/spending_by_award/`. If you omit it, you get a 422. The gem always sends a default field set; callers can override.
- **Stale recipient profiles.** `/recipient/{uei}/` lags by months. Recent registrations may 404.
- **Award updates are batch.** The `Last Modified Date` advances when Treasury's nightly load runs, not when the source FPDS record changes. There's typically a ~24-72hr lag.

## Useful query patterns

- **Recompete detection:** filter by `awarding_agency_name` + `naics_code` + `period_of_performance.end_date` in the next 12-24 months. See [[cross-referencing]].
- **Incumbent lookup:** filter by `piid` (the solicitation number from SAM, sometimes) or by `recipient_uei` (more reliable).
- **Agency spending profile:** filter by agency + fiscal year, aggregate obligation.

## Open questions for the maintainer

> ⚠️ FILL IN: Have you seen any sustained-rate behavior different from the ~10-15 req/sec ceiling? Note current observation.
>
> ⚠️ FILL IN: Subawards and sub-recipient data — in scope for v1 or deferred? (USASpending has `/subawards/` but it's noisy.)
>
> ⚠️ FILL IN: `/bulk_download/` async flow — keep it deferred? Confirm.
