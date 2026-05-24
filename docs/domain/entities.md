# SAM Entities — registration, classifications, exclusions, ownership

`Contractkit::Sam::Entities` is the client for SAM.gov's Entity
Management API (`/entity-information/v3/entities`). It enriches a
`Contractkit::Recipient` with the full SAM registration record:
status, expiration, CAGE, NAICS list, business types, SBA
certifications, exclusion status, and corporate-hierarchy owner
references.

```ruby
# USASpending-built Recipient (un-enriched, what Award.search produces)
award = Contractkit::Award.search(...).first
award.recipient.cage_code           # => nil
award.recipient.excluded?           # => nil

# Enrich via SAM
sam = Contractkit::Recipient.find_entity(award.recipient.uei)
sam.cage_code                       # => "12345"
sam.registration_status             # => "Active"
sam.sam_expiration_date             # => #<Date 2027-04-10>
sam.registration_expired?           # => false
sam.excluded?                       # => false
sam.business_types.first            # => #<Contractkit::CodedValue code:"2X" description:"For Profit Organization">
sam.sba_business_types.first.code   # => "A6"  (8(a))
sam.naics_list.first[:primary]      # => true
sam.immediate_owner.name            # => "ACME HOLDINGS CORP"
```

## Two construction paths, one class

| Path | What populates | Use when |
|---|---|---|
| `Contractkit::Award.search` → recipient on the row | name, uei, duns, recipient_id | Bulk pipelines — every other field is nil |
| `Contractkit::Recipient.find_entity(uei)` | Everything | Vendor-fitness checks, exclusion gating |

Enrichment is **opt-in** — Award/IDV parsing never makes a SAM round
trip on the consumer's behalf. This keeps bulk pipelines from
fan-outing N SAM calls per page.

## Exclusion handling — single dataset, deferred separate client

SAM exposes two datasets that touch exclusion:

1. The Entity Management response includes `exclusionStatusFlag` and
   (sometimes) a nested `exclusionInformation` sub-document with a
   description.
2. A separate SAM Exclusions API (`/data-services/v1/exclusions`)
   provides the full exclusion record history with dates and
   programmes.

**Decision (M4):** the gem reads exclusion *status* off the entity
response only. That's enough to answer "is this vendor debarred /
suspended right now?". The full exclusion *history* (when, by whom,
which programme) is **deferred** — a dedicated
`Contractkit::Sam::Exclusions` client is a follow-up issue. When you
need the history (e.g. compliance audit trail), file a follow-up; for
yes/no vendor-fitness gating, today's surface is sufficient.

## Date handling

All SAM date fields are parsed to `Date` (not `DateTime`). Empty /
missing → nil.

## Owner references

`immediate_owner` and `highest_owner` are tiny
`Contractkit::OwnerReference` value objects with `uei`, `name`, and
`cage_code` — the minimal identity triple SAM publishes for owner
records. Predecessors (where SAM lists them) are an array of the same
shape.

## No vendor-fitness scoring

The gem does not compute a "vendor fitness score", a "win probability
adjustment based on exclusions", or any other ranking. It surfaces
the raw SAM data; consumers apply their own rules.

## References

- `docs/research/tango-findings.md` §1 (Entity model), §4 (corporate
  hierarchy)
- SAM Entity Management API: https://open.gsa.gov/api/entity-api/
- SAM Exclusions API (deferred): https://open.gsa.gov/api/exclusions-api/
