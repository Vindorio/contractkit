# Indefinite-Delivery Vehicles (IDVs)

An IDV is the USASpending "category" for any contract **vehicle** — an
umbrella agreement under which one or more child task / delivery orders
are placed over time. Includes:

- IDC (Indefinite Delivery Contract)
- GWAC (Government-Wide Acquisition Contract)
- BPA (Blanket Purchase Agreement)
- BOA (Basic Ordering Agreement)
- FSS (Federal Supply Schedule)

ContractKit models IDVs as a **separate class** from definitive
contracts — `Contractkit::Idv` is parallel to `Contractkit::Award`,
not a subclass. Both originate from USASpending but have different
lifecycle fields (IDVs carry `last_date_to_order`; awards carry
`period_of_performance.end_date`).

## Recompete signal: `last_date_to_order`

The primary recompete signal lives on the IDV, not the child task
orders. When an IDV's `last_date_to_order` is within the recompete
window (default 12 months out — see
`Contractkit::Recompete::DEFAULT_WINDOW_MONTHS`), the vehicle is a
candidate for follow-on solicitation.

```ruby
Contractkit::Recompete.expiring(within: 12) do |match|
  puts match.award.piid          # IDV PIID
  puts match.matching_opportunities.map(&:notice_id)
end
```

## Parent / child traversal

```
Idv  ──── child task orders (Award where parent_piid == idv.piid)
 │         │
 │         └── parent_idv (lookup back via parent_piid)
 │
 └── Idv#child_awards(client:)  →  [Award, Award, ...]
```

```ruby
# Given an Award (task order), find its parent IDV:
order = Contractkit::Award.search(filters: {...}).first
idv = order.parent_idv

# Given an IDV, list its children:
idv = Contractkit::Idv.search(filters: {...}).first
orders = idv.child_awards
```

## Filtering for IDVs

USASpending's `spending_by_award` shares its endpoint between contracts
and IDVs — the distinction is `award_type_codes`. ContractKit injects
`Contractkit::Idv::IDV_AWARD_TYPE_CODES` automatically when you call
`Contractkit::Idv.search`. Don't override `award_type_codes` unless you
know exactly which slice you want.

## Field nullability

Vehicle-level rollups (`child_award_count`,
`child_award_total_obligation`, `grandchild_*`) are populated only when
the detail endpoint returns them — bulk search responses leave them
nil. Same caveat as `Contractkit::Award`'s competition fields; see
`docs/domain/award-pricing.md`.

## No scoring

The gem surfaces raw IDV data and does no inference about "is this
recompetable?", "who will win the recompete?", etc. See
`docs/domain/recompete.md` for the pairing helper and its explicit
non-goal of ranking.

## References

- `docs/research/tango-findings.md` §1 (Model Map — IDV), §2
  (Recompete-Relevant Fields)
- USASpending endpoints: https://api.usaspending.gov/docs/endpoints
