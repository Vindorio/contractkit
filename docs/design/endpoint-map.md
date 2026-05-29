# Endpoint Map

> **Purpose:** Every upstream API endpoint the gem touches, what calls
> it, parameter shapes, pagination semantics, and quirks.
>
> **Audience:** AI agents and developers debugging HTTP-level behavior.

---

## SAM.gov

### `GET /opportunities/v2/search`

**The workhorse.** Listing + filter + pagination. 95% of the gem's SAM
traffic.

| Property | Value |
|---|---|
| Base URL | `https://api.sam.gov/opportunities/v2/search` |
| Auth | Query param `api_key=<key>` |
| Pagination | Offset/limit. `limit` max 1000, `offset` zero-based |
| Rate limit | ~20 req/min sustained (conservative default) |
| Date format | `MM/DD/YYYY` (`postedFrom`, `postedTo`) |

**Called by:**
- `Contractkit::Opportunity.search` → `OpportunitySearch` → `Sam::Client#raw_search`
- `Contractkit::Opportunity.modified_since` (wraps `.search` with date filter)
- `Contractkit::Recompete.expiring` (to find matching SAM opportunities)

**Key params:**
| Param | Type | Notes |
|---|---|---|
| `api_key` | String | Required |
| `limit` | Integer | Page size, max 1000 |
| `offset` | Integer | Zero-based row index |
| `postedFrom` | String | `MM/DD/YYYY`, inclusive |
| `postedTo` | String | `MM/DD/YYYY`, inclusive |
| `ncode` | String | Single NAICS code |
| `ptype` | String | Default: `"p,o"` (presolicitation + solicitation) |
| `typeOfSetAside` | String | Single set-aside code |
| `state` | String | 2-letter state code |
| `deptname` | String | Agency name (case-sensitive exact match) |

**Response shape:**
```json
{
  "totalRecords": 3847,
  "limit": 100,
  "offset": 0,
  "opportunitiesData": [ { ...notice... } ],
  "links": [ {"rel": "self", "href": "..."}, {"rel": "next", "href": "..."} ]
}
```

**Quirks:**
- Offsets near the tail (>9000) get noticeably slower
- Sorting unstable across pages — duplicates and misses possible
- `naicsCode` sometimes returned as integer (gem zero-pads to 6 chars)
- `placeOfPerformance.state` can be string or `{code, name}` object

### `GET /opportunities/v2/{noticeId}`

Single notice lookup by SAM's `noticeId`.

| Property | Value |
|---|---|
| Auth | Query param `api_key=<key>` |
| Returns | Single notice in `opportunitiesData[0]` |

**Called by:** `Contractkit::Opportunity.find(notice_id)`

### `GET /entity-information/v3/entities`

SAM Entity Management API. Returns full entity registration record.

| Property | Value |
|---|---|
| Base URL | `https://api.sam.gov/entity-information/v3/entities` |
| Auth | `x-api-key` header (note: different from opportunities v2) |
| Returns | Entity registration, business types, exclusions, ownership |

**Called by:** `Contractkit::Recipient.find_entity(uei)` → `Sam::Entities`

**Key params:**
| Param | Type | Notes |
|---|---|---|
| `ueiSAM` | String | 12-char UEI |
| `cageCode` | String | Alternate lookup key |

**Response includes:**
- `entityRegistration.registrationStatus`, `samExpirationDate`
- `entityRegistration.businessTypes[]` — `(businessTypeCode, businessTypeDescription)` pairs
- `entityRegistration.sbaBusinessTypes[]` — SBA certifications
- `entityRegistration.naicsList[]` — `{naicsCode, isPrimary}`
- `entityInformation.exclusionStatusFlag`
- `entityInformation.immediateOwner`, `highestOwner` — `{uei, entityName, cageCode}`

---

## USASpending.gov

### `POST /api/v2/search/spending_by_award/`

**Primary USASpending endpoint.** Filtered award listing. POST with
JSON body — not GET.

| Property | Value |
|---|---|
| Base URL | `https://api.usaspending.gov/api/v2/search/spending_by_award/` |
| Auth | None (send a polite `User-Agent`) |
| Pagination | Page-based. `limit` max 100, `page` 1-indexed |
| Rate limit | ~10-15 req/sec sustained before latency climbs |

**Called by:**
- `Contractkit::Award.search` → `AwardSearch` → `Usaspending::Client#raw_search`
- `Contractkit::Idv.search` (same endpoint, different `award_type_codes`)
- `Contractkit::CrossReference.awards_for` (via `Award.search`)
- `Contractkit::Recompete.expiring` (via `Idv.search` + `Award.search`)
- `Contractkit::Idv.find_by_piid`

**Request body:**
```json
{
  "filters": {
    "award_type_codes": ["A", "B", "C", "D"],
    "naics_codes": ["541512"],
    "time_period": [{"start_date": "2026-01-01", "end_date": "2026-12-31"}],
    "agencies": [{"type": "awarding", "tier": "toptier", "name": "Department of Defense"}]
  },
  "fields": ["Award ID", "Award Amount", "Recipient Name", "..."],
  "page": 1,
  "limit": 100,
  "sort": "Action Date",
  "order": "desc"
}
```

**Response shape:**
```json
{
  "results": [ { ...award... } ],
  "page_metadata": {
    "page": 1,
    "hasNext": true,
    "total": 1234,
    "last_page": 13
  }
}
```

**Key `fields` (25 shipped by default):**
`Award ID`, `generated_unique_award_id`, `piid`, `parent_award_piid`,
`Award Type`, `Award Amount`, `Base + All Options Value`,
`Base + Exercised Options Value`, `Total Contract Value`,
`Recipient Name`, `recipient_id`, `uei`, `recipient_duns`,
`Awarding Agency`, `Awarding Sub Agency`, `Funding Agency`,
`naics_code`, `psc_code`, `Start Date`, `End Date`,
`Last Modified Date`, `Place of Performance State`,
`Description`, `Type of Set Aside`, `action_date`

**Quirks:**
- `fields` is mandatory — omit it and get 422
- Past `page=1000` (~100k records) can time out
- Sort key strings are case- and space-sensitive (`"Action Date"` works, `"action_date"` doesn't)
- `award_type_codes` for contracts: `A`, `B`, `C`, `D` — for IDVs: `IDV_AWARD_TYPE_CODES` constant

### `GET /api/v2/awards/{generated_unique_award_id}/`

Single-award detail. Richer response than spending_by_award — includes
competition fields, three-tier pricing, and a different field shape.

| Property | Value |
|---|---|
| Returns | Full award detail with nested agency/recipient objects |
| Fields | `total_obligation`, `base_exercised_options`, `base_and_all_options`, `latest_transaction_contract_data.*` |

**Called by:** `Contractkit::Usaspending::ResponseParser.parse_detail`

**Key differences from spending_by_award:**
- Agency is nested: `awarding_agency.toptier_agency.name` / `subtier_agency.name`
- Pricing fields: `total_obligation` (not `Award Amount`),
  `base_exercised_options` (not `Base + Exercised Options Value`)
- Competition fields live under `latest_transaction_contract_data`

### `GET /api/v2/recipient/{uei}/`

Recipient lookup. Legacy path is `/recipient/duns/{uei}/` (still works
after the 2022 UEI migration).

| Property | Value |
|---|---|
| Returns | Recipient profile: name, UEI, DUNS, business types, parent info |

**Called by:** `Contractkit::Recipient.find(uei)` →
`Usaspending::Client#raw_recipient`

### `POST /api/v2/transactions/`

Per-award modification history. Returns a paginated list of
transaction records.

| Property | Value |
|---|---|
| Filters | `award_id` (generated_unique_award_id) |
| Returns | Array of transaction records with `modification_number`, `action_date`, `federal_action_obligation`, `action_type` |

**Called by:** `Contractkit::Transaction.for_award(award_id)` →
`Usaspending::Client#transactions`

**Key fields per transaction:**
- `id` — transaction ID
- `modification_number` — `"P00000"` is base award
- `action_date` — when the mod was signed
- `federal_action_obligation` — per-mod delta (can be negative)
- `action_type` — `{code, description}` (e.g. `"G"` = exercise option)
- `description` — CO free text

### `POST /api/v2/subawards/`

One-level prime → sub teaming data. Returns subaward records for a
specific award.

| Property | Value |
|---|---|
| Filters | `award_id` (generated_unique_award_id) |
| Returns | Array of subaward records with both prime and sub UEIs |

**Called by:** `Contractkit::Subaward.for_award(award_id)` →
`Usaspending::Client#subawards`

**Key fields per subaward:**
- `id`, `subaward_number`, `action_date`, `amount`
- `prime_award_id`, `prime_award_piid`
- `prime_recipient_uei`, `prime_recipient_name`
- `sub_recipient_uei`, `sub_recipient_name`
- `naics_code`, `psc_code`

---

## Gem → API mapping summary

| Gem Resource | API Endpoint | Method | Auth |
|---|---|---|---|
| `Opportunity.search` | `sam.gov/opportunities/v2/search` | GET | `api_key` query |
| `Opportunity.find` | `sam.gov/opportunities/v2/{id}` | GET | `api_key` query |
| `Award.search` | `usaspending.gov/search/spending_by_award/` | POST | None |
| `Idv.search` | `usaspending.gov/search/spending_by_award/` | POST | None |
| `Transaction.for_award` | `usaspending.gov/transactions/` | POST | None |
| `Subaward.for_award` | `usaspending.gov/subawards/` | POST | None |
| `Recipient.find` | `usaspending.gov/recipient/{uei}/` | GET | None |
| `Recipient.find_entity` | `sam.gov/entity-information/v3/entities` | GET | `x-api-key` header |
| `CrossReference.awards_for` | `usaspending.gov/search/spending_by_award/` | POST | None |
| `Recompete.expiring` | both (SAM + USASpending) | GET + POST | key + none |
