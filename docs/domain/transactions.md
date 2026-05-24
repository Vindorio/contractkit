# Transactions — modification history

Every action on a federal contract — the base award, every option
exercise, every ceiling increase, every administrative correction — is
recorded as a separate **transaction** in USASpending. The award you
see today is the *latest snapshot*; the transaction stream is the
*history* that produced it.

`Contractkit::Transaction` surfaces one row from
`/api/v2/transactions/`. The sum of `federal_action_obligation` across
all transactions for an award reconstructs that award's current
`total_obligation` (modulo rounding and de-obligation corrections).

## Fields

| Field | Type | Notes |
|---|---|---|
| `id` | Integer | USASpending transaction id |
| `modification_number` | String | "P00000" is the base award; "P00001" etc. are mods |
| `action_date` | Date | When the modification was signed |
| `federal_action_obligation` | BigDecimal | Per-modification delta (may be negative for de-obligations) |
| `action_type` | `CodedValue` | See common codes below |
| `type` | `CodedValue` | Award type at time of modification (can change across mods) |
| `description` | String | Free text from the contracting officer |

Loan-only fields (`face_value_loan_guarantee`,
`original_loan_subsidy_cost`) are populated for loan awards; nil for
contracts.

## Common `action_type` codes

| Code | Description |
|---|---|
| `A` | Additional work (new agreement, funding only action) |
| `B` | Supplemental agreement for work within scope |
| `C` | Funding only action |
| `D` | Change order |
| `E` | Termination for default |
| `F` | Termination for convenience |
| `G` | Exercise an option |
| `H` | Definitize change order / letter contract |
| `J` | Novation agreement |
| `K` | Close out |
| `L` | De-obligation |
| `M` | Other administrative action |

(Codes per FPDS-NG data dictionary; consumers should consult the
USASpending docs for the canonical list at fetch time — it does
evolve.)

## Option exercise inference

USASpending **does not surface an explicit "this transaction was an
option exercise" flag**. Consumers infer it by parsing `action_type`
and `description`:

- `action_type.code == "G"` is the closest explicit signal ("exercise
  an option") but is not universally used.
- Many agencies record option exercises as `action_type.code == "B"`
  (supplemental, within scope) with description matching `/option/i`.
- Some use `action_type.code == "C"` (funding only) for option years.

The gem **does not implement this inference** — it surfaces the raw
`action_type` + `description` and lets consumers apply their own
rules. See `docs/research/tango-findings.md` §2 for the rationale.

## Usage

```ruby
award = Contractkit::Award.search(...).first
txs = award.transactions    # auto-paginated → Array<Transaction>

# Or stream batches:
client = Contractkit::Usaspending::Client.new
client.transactions(award_id: award.award_id) do |batch|
  batch.each { |row| ... }
end
```

`Contractkit::Idv#transactions` works the same way.

## No derived booleans

No `#option_exercise?`, no `#ceiling_increase?`. Consumer concern.

## References

- `docs/research/tango-findings.md` §2 (Option exercise via transaction
  parsing), §3 (per-mod pricing)
- USASpending: https://api.usaspending.gov/docs/endpoints
