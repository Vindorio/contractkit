# Subawards — prime / sub teaming

`Contractkit::Subaward` surfaces one subaward row from USASpending —
the prime award and one downstream sub on a single record. Both sides
of the pair are denormalised on the row (`prime_recipient_uei` and
`sub_recipient_uei` both present) so consumers can query teaming
patterns in either direction without a join.

## What's in scope

- One level: prime → direct sub.

## What's out of scope

- **Multi-tier** (sub-to-sub): not present in USASpending. The gem
  does not invent it.
- **Pre-FFATA awards**: subaward reporting is only required for
  contracts > $30k (FFATA, 2006). Smaller awards have no subaward
  records; that's not a bug.
- **Compliance is imperfect**: even above the threshold, primes
  under-report. Absence of a subaward row does not prove no sub
  exists. Don't draw negative conclusions.

## Fields

| Field | Type | Notes |
|---|---|---|
| `id` | String | USASpending internal id |
| `subaward_number` | String | Sub-award number reported by prime |
| `action_date` | Date | When the sub was placed |
| `amount` | BigDecimal | Sub-award dollar amount |
| `prime_award_id` | String | `generated_unique_award_id` of the prime |
| `prime_award_piid` | String | Prime's PIID |
| `prime_recipient_uei` / `_name` | String | Prime side |
| `sub_recipient_uei` / `_name` | String | Sub side |
| `sub_recipient_address` | Hash | `{city:, state:, country:}` (compact — only populated fields) |
| `naics_code`, `psc_code` | String | NAICS / PSC of the subawarded work where reported |

## Usage

```ruby
# All subs under one prime
award = Contractkit::Award.search(filters: {...}).first
subs = award.subawards          # auto-paginated → Array<Subaward>

# Bulk search (e.g. all subs in a NAICS over a date range)
Contractkit::Subaward.search(filters: {
  "naics_codes" => ["541512"],
  "time_period" => [{ "start_date" => "2026-01-01", "end_date" => "2026-12-31" }]
}) do |sub|
  ...
end
```

## No teaming-score logic

The gem does not compute teaming-graph metrics, repeat-pair counts,
geographic teaming scores, etc. Consumer's job.

## References

- `docs/research/tango-findings.md` §4 (Subaward / Relationship Network)
- USASpending: https://api.usaspending.gov/docs/endpoints
