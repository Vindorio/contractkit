# FPDS — Federal Procurement Data System

> **Purpose:** What FPDS is, how it relates to USASpending.gov, and
> what it means for contractkit consumers.
>
> **Audience:** AI agents, new developers who hear "FPDS" referenced
> throughout the gem's code and docs and need to understand what it is.

Related: [[usaspending]], [[sam-gov]], [[../design/data-models]]

---

## What FPDS is

FPDS (Federal Procurement Data System) is the government's **system of
record** for federal contract actions. Every contract award,
modification, delivery order, and BPA call — above the micro-purchase
threshold (~$10k for most agencies) — is reported to FPDS by the
contracting officer, typically within 3 business days of the action.

FPDS is operated by GSA. It's the upstream database; everything else
(USASpending.gov, USAID's ForeignAssistance.gov, the IT Dashboard)
reads from it.

## What FPDS is NOT

- **Not a public API.** FPDS does not expose a REST API for querying.
  The public access path goes through USASpending.gov.
- **Not the contracting system.** FPDS is a *reporting* system, not a
  *transaction* system. Contracting officers use SAM.gov, SPS, or
  agency-specific tools to write contracts; they *report* the results
  to FPDS afterward.
- **Not real-time.** There's typically a 24-72 hour lag between a
  contract action and its appearance in FPDS, and another 24-72 hours
  before the nightly load propagates it to USASpending.gov.

## Relationship to USASpending.gov

```
Contracting Officer
       │
       │  writes contract in SAM.gov / SPS / agency tool
       ▼
  FPDS (system of record)  ──── nightly load ────▶  USASpending.gov
       │                                                  │
       │                                                  │
       ▼                                                  ▼
  USASpending's             USASpending.gov              Public API
  internal Django           (web UI for citizens)        (HTTP JSON)
  backend
```

USASpending.gov is Treasury's public-facing presentation of FPDS data.
The two share the same underlying records, but:

1. **USASpending has a public API; FPDS does not.** When the gem calls
   `POST /api/v2/search/spending_by_award/`, it's hitting
   USASpending's API, which is reading from USASpending's own copy of
   FPDS data.

2. **USASpending provides the full detail shape** via
   `/api/v2/awards/{id}/`. This endpoint returns FPDS-derived fields
   like `extent_competed`, `number_of_offers_received`,
   `solicitation_procedures`, and `type_of_contract_pricing` that
   aren't available in the bulk search endpoint.

3. **Some fields are FPDS-only.** The `action_type` code on a
   transaction (e.g. `"G"` = exercise option) comes from FPDS's
   modification reporting. These codes are defined by the FPDS-NG
   data dictionary.

## FPDS agency codes

FPDS assigns every reporting entity a **4-digit alphanumeric agency
code**. These codes appear in:

- SAM.gov's `fullParentPathCode` — dot-separated hierarchy: `"9700.5700.FA8773.FA8771"`
- USASpending's `awarding_agency.subtier_agency.code`
- USASpending's `funding_agency.subtier_agency.code`

The gem does NOT use FPDS agency codes directly as primary identifiers.
Instead, it normalizes to **top-tier canonical `Agency.code`** (e.g.
`"DOD"`, `"VA"`, `"GSA"`) using the curated alias table. This is
because:

- FPDS codes exist at the sub-tier / office level, which v0.1 doesn't
  normalize
- The same agency can appear under different FPDS codes depending on
  the reporting office
- A canonical short code (`"DOD"`) is more useful for indexed queries
  than a 4-digit FPDS code (`"9700"`)

See [[agency-normalization]] for the full rationale.

## FPDS award type codes

The `award_type_codes` filter on USASpending's spending_by_award
endpoint uses FPDS-derived categories:

| Code | Description | Used by gem for |
|---|---|---|
| `A` | BPA Call | Award search |
| `B` | Purchase Order | Award search |
| `C` | Delivery Order | Award search |
| `D` | Definitive Contract | Award search |
| `IDV_A` | BPA | Idv search |
| `IDV_B` | BOA | Idv search |
| `IDV_C` | FSS | Idv search |
| `IDV_D` | GWAC | Idv search |
| `IDV_E` | IDC | Idv search |

The gem's `Contractkit::Award.search` defaults to `A, B, C, D` (all
contract types). `Contractkit::Idv.search` injects the
`IDV_AWARD_TYPE_CODES` constant automatically.

## FPDS transaction `action_type` codes

When calling `Award#transactions`, the `action_type` field on each
`Transaction` comes from FPDS's modification classification. Common
codes:

| Code | Description | Implication for contractkit |
|---|---|---|
| `A` | Additional work (new agreement) | New scope or funding |
| `B` | Supplemental agreement (within scope) | Often an option exercise |
| `C` | Funding only action | Incremental funding |
| `D` | Change order | Scope change |
| `G` | Exercise an option | **Closest explicit option signal** |
| `H` | Definitize letter contract | Convert temporary to permanent |
| `K` | Close out | End of contract |
| `L` | De-obligation | Money returned |

The gem does NOT infer "this was an option exercise" from action_type
codes. It surfaces the raw `CodedValue` and lets consumers apply their
own rules. See [[transactions]] §"Option exercise inference".

## Relevance to contractkit

**The gem never talks to FPDS directly.** FPDS is the upstream data
source that USASpending.gov ingests. Everything the gem surfaces —
awards, IDVs, transactions, competition fields — ultimately originated
in FPDS.

When the gem's docs or code refer to "FPDS agency codes", "FPDS award
types", or "FPDS action codes", they're referencing the classification
system that USASpending inherited from FPDS.

## Future consideration: FPDS as a third source

The PRD mentions FPDS as a possible **third data source** in v0.3+:

> FPDS predates USASpending and offers some fields USASpending
> doesn't (e.g. detailed transaction history).

This would mean writing a client that queries FPDS directly (likely
via bulk data downloads rather than an API) and reconciling the
differences with USASpending's representation. This is NOT committed
work — it's listed as a future consideration only.

## Key takeaways for AI agents

1. **The gem wraps USASpending.gov, which wraps FPDS.** You're two
   hops away from the source of truth. Expect ~48-96 hours of lag
   from contract signature to gem visibility.

2. **FPDS codes are referenced but not used as primary keys.** The
   gem normalizes agencies to short canonical codes (`"VA"`) rather
   than FPDS numeric codes (`"3600"`).

3. **Transaction action_type comes from FPDS.** The `CodedValue` on
   `Transaction#action_type` is FPDS's classification. Option
   exercise inference is the consumer's job.

4. **Competition fields are FPDS-derived.** `extent_competed`,
   `number_of_offers_received`, `type_of_contract_pricing`,
   `solicitation_procedures` — all originate in FPDS but are only
   accessible via USASpending's single-award detail endpoint.

## References

- FPDS-NG Data Dictionary: https://www.fpds.gov/downloads/FPDS-Data-Dictionary.pdf
- USASpending API docs: https://api.usaspending.gov/docs/endpoints
- GSA Federal Hierarchy: https://www.gsa.gov/reference/geographic-locator-codes/federal-hierarchy
