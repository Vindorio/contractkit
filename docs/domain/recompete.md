# Recompete — time-forward cross-reference

`Contractkit::Recompete.expiring(within:)` is the time-forward sibling
of `Contractkit::CrossReference.awards_for`:

| | direction | question |
|---|---|---|
| `CrossReference.awards_for` | time-backward | "Given this opportunity, what prior awards relate?" |
| `Recompete.expiring` | time-forward | "What IDVs / contracts are about to expire — and what active solicitations might be their follow-on?" |

Combined, they give consumers the historical incumbent picture and the
upcoming recompete pipeline from one gem.

## Usage

```ruby
Contractkit::Recompete.expiring(within: 12) do |match|
  match.award                  # Idv or Award
  match.matching_opportunities # Array<Opportunity> (may be empty)
end

# Or as Enumerator:
Contractkit::Recompete.expiring(within: 6).first(10)
```

`within:` accepts:

- Plain Integer (months)
- Anything responding to `#in_months` (e.g. `ActiveSupport::Duration`)

This keeps ActiveSupport off the gem's required dependency list while
playing nicely when callers have it loaded.

## Join strategy

The same vocabulary as `CrossReference.awards_for` —
`match: [:agency, :naics]` is the workhorse. PSC and state are
available as tighteners. **There is no primary key between SAM
opportunities and USASpending awards**; the join is heuristic and
inherently imprecise. See `docs/domain/cross-referencing.md` for the
underlying rationale.

## Window semantics

The window is **closed on both ends**: an award expires "within 12
months" if its `last_date_to_order` (IDV) or `period_of_performance.
end_date` (contract) falls in `[today, today + 12 months]`. Past
expirations are excluded — that's `CrossReference.awards_for`'s
domain.

## IDV vs Contract slices

The helper queries IDVs first (using `Contractkit::Idv::IDV_AWARD_TYPE_CODES`)
and then definitive contracts. IDVs are prioritised because their
`last_date_to_order` is a stronger recompete signal than a contract's
PoP end (a contract may simply close without a follow-on; an IDV
expiring usually triggers a new vehicle competition).

## Memory

The helper streams — it never accumulates all expiring awards in
memory at once. The Enumerator and block forms both yield per-match;
no intermediate Array unless the consumer asks for one (`.to_a`,
`.first(n)`).

## No scoring

The gem does not rank matches by likelihood, win probability, or any
other heuristic. Consumers receive the raw `(award,
matching_opportunities)` pairs and apply their own ranking. Vindor's
scoring lives in Vindor — that's deliberate.

## Imprecision caveats

- Some recompetes appear on SAM under a different agency name than
  the original award (delegated procurements). `match: [:naics]` only
  may catch them at the cost of false positives.
- Some "expiring" IDVs are followed by a contract extension, not a
  new solicitation — there will be no matching opportunity, but the
  award still expires.
- An empty `matching_opportunities` list does **not** mean "no
  recompete coming" — it means none has been posted yet (or the
  agency post pattern doesn't match the join keys).

## References

- `docs/research/tango-findings.md` §2 (Recompete-Relevant Fields),
  §6(b) (no explicit recompete flag)
- `Contractkit::CrossReference` — the time-backward sibling
- Issue #41
