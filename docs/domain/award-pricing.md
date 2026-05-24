# Award Pricing — three-tier model

USASpending's contract awards carry **three** pricing magnitudes that
consumers routinely confuse. ContractKit surfaces them as three distinct
BigDecimal fields on `Contractkit::Award` so the relationship is
explicit:

```
obligated_amount  ≤  base_and_exercised_options_value  ≤  base_and_all_options_value
(total_obligation)                                       (total_contract_value)
                                                         (ceiling)
```

| Field | Meaning |
|---|---|
| `obligated_amount` / `total_obligation` | Money actually obligated to date — what Treasury sees as "spent" against this award. |
| `base_and_exercised_options_value` | Sum of base period + options the government has formally exercised. |
| `base_and_all_options_value` / `total_contract_value` / `ceiling` | Maximum potential value if every option is exercised — the contract ceiling. |

The same dollar amount typically flows from left to right over time as
the award matures (options exercised, more money obligated). The
relationship lets consumers tell **option exercises** (left bucket
grows while ceiling stays flat) apart from **ceiling growth** /
modifications (right bucket grows).

## Endpoint coverage

USASpending exposes these via two separate paths with different field
shapes:

| Field | `spending_by_award` (bulk) | `/api/v2/awards/{id}/` (detail) |
|---|---|---|
| `obligated_amount` | `Award Amount` | `total_obligation` |
| `base_and_exercised_options_value` | `Base + Exercised Options Value` (subset) | `base_exercised_options` |
| `base_and_all_options_value` | `Base + All Options Value` | `base_and_all_options` |
| `total_contract_value` | `Total Contract Value` (subset) | `total_contract_value` |
| `number_of_offers_received` | **detail-only** | `latest_transaction_contract_data.number_of_offers_received` |
| `extent_competed` | **detail-only** | `latest_transaction_contract_data.extent_competed[_description]` |
| `type_of_contract_pricing` | **detail-only** | `latest_transaction_contract_data.type_of_contract_pricing[_description]` |
| `solicitation_procedures` | **detail-only** | `latest_transaction_contract_data.solicitation_procedures[_description]` |

The competition fields (`extent_competed`, `type_of_contract_pricing`,
`solicitation_procedures`, `number_of_offers_received`) are **only
populated when you parse the single-award detail endpoint**. Bulk
search rows leave them nil. Use
`Contractkit::Usaspending::ResponseParser.parse_detail` against the
detail endpoint shape to populate them; the bulk
`ResponseParser.parse` path leaves them nil with a YARD note.

## CodedValue pairs

Fields that USASpending exposes as `(code, description)` pairs are
surfaced as `Contractkit::CodedValue` value objects with `.code` and
`.description` readers. Examples: `extent_competed.code = "A"`,
`extent_competed.description = "FULL AND OPEN COMPETITION"`.

## No scoring

The gem exposes these fields and does no derived classification
("competitively awarded?", "small-business set-aside?", "is option
exercise?"). Consumers apply their own rules.

## References

- `docs/research/tango-findings.md` §3 (Pricing-relevant fields)
- USASpending: https://api.usaspending.gov/api/v2/awards/{id}/
