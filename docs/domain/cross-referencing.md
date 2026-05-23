# Cross-Referencing SAM Opportunities with USASpending Awards

> **Purpose:** How to link a future contract opportunity (SAM) to relevant past awards (USASpending) when there is no shared primary key. This is the gem's flagship value-add and the trickiest piece of domain logic.
>
> **Audience:** Contractkit contributors; downstream developers building recompete detection, incumbent intel, or capture-research tools.

Related: [[sam-gov]], [[usaspending]], [[agency-normalization]], [[naics-and-setasides]]

---

## The problem in one paragraph

SAM and USASpending are two separate IT systems run by two separate agencies (GSA and Treasury). They share an underlying procurement reality but no shared primary key. The same contract action shows up in SAM as a *notice* and in USASpending as an *award*, but the identifiers, agency names, set-aside encodings, and timestamps are all subtly different. Joining them is a fuzzy-match problem with no perfect answer — but a few high-signal patterns get you 80% of the way.

## Available join keys, ranked by reliability

| Field | Lives in SAM | Lives in USASpending | Reliability | Notes |
|---|---|---|---|---|
| Recipient UEI | Award notices only | Yes | **Highest, when present** | Definitive when both sides have it. Only present on SAM award notices, not on solicitations. |
| NAICS code | Yes | Yes | High | Exact match. The workhorse signal. |
| PSC code | Yes (`classificationCode`) | Yes | High | Complements NAICS; together they tighten matches considerably. |
| Awarding agency | Yes (hierarchical) | Yes (hierarchical) | Medium | Needs normalization — see [[agency-normalization]]. |
| Solicitation number / PIID | Yes | Sometimes | **Lower than you'd expect** | See "Why solicitation number is unreliable" below. |
| Set-aside type | Yes | Yes | Medium | Useful as a tightening signal, not as a primary join. |
| Period-of-performance dates | Solicitation gives expected start; awards have actual | Yes | Medium | Useful for recompete-window math, not for identity. |
| Place of performance | Yes | Yes | Low | Frequently disagrees due to admin geography vs delivery location. |

## Why solicitation number is unreliable

You'd reasonably expect that the solicitation number on a SAM notice (`FA8771-26-R-0042`) is the same string that appears on the eventual USASpending award (`piid`). It often is. It also often isn't, for these reasons:

1. **Sole-source awards** never have a SAM solicitation, so there's no number to match.
2. **Task orders against IDIQs** have a different `piid` than the IDIQ's SAM number — the SAM notice was for the parent vehicle, not the specific order.
3. **Solicitation numbering changes during the procurement.** Amendments sometimes re-number; agencies sometimes append suffixes (`-0042-001`) inconsistently.
4. **Free-text contamination.** Many SAM notices put descriptive text in the `solicitationNumber` field (`"Notice ID 1234567"`, `"See description"`). USASpending's `piid` is always cleaner.
5. **Recompete renaming.** A recompete of last year's `36C24E25Q0001` may show up as `36C24E26Q0001` — same scope, new fiscal year, deliberately different number.

**Empirical hit rate:** in past pipeline runs, exact `solicitationNumber == piid` matches identify only ~30-40% of the related awards a human reviewer would call "related." Use it as a tie-breaker, not as the primary join.

> ⚠️ FILL IN: Update the hit-rate observation with whatever the current Rails pipeline measures. Source it (which agencies, which date window).

## The primary matching strategy

The gem's default `Opportunity#related_awards` uses **agency + NAICS** as the primary join, with PSC as a tightener when both sides have it.

```
match(opportunity, award) := normalize(opp.agency) == normalize(award.awarding_agency)
                           AND opp.naics == award.naics
                           [AND opp.psc == award.psc, if both present]
                           AND award.period.end_date BETWEEN now AND now + 24 months
                                                  (for recompete detection)
```

The end-date window is the recompete heuristic — a contract whose period of performance ends soon is the candidate for the upcoming opportunity. Without it, you match every historical award the agency ever placed under that NAICS, which is too noisy to be useful.

**Configurable knobs in the gem:**

```ruby
opp.related_awards(
  match: [:agency, :naics],          # default; add :psc for tighter
  lookback: 3.years,                 # awards whose period ENDED within window
  ending_window: 24.months,          # awards whose period ENDS within window (recompete signal)
  limit: 50
)
```

## What "recompete" looks like in the data

A recompete — the upcoming re-procurement of work the government is already buying — has this fingerprint:

1. A **SAM opportunity** (presolicitation or solicitation) for some NAICS at some agency.
2. One or more **USASpending awards** with:
   - Same agency (or sub-agency tier within the same department),
   - Same NAICS,
   - Period of performance ending within the next ~12-24 months,
   - Often (not always) similar award description / scope language,
   - Often a single dominant recipient (the incumbent).

The presence of an incumbent — one recipient with >50% of the obligation across recent matching awards — is the cleanest recompete signal. The gem exposes this as `Opportunity#likely_incumbent` (returns the `Recipient` or `nil`).

## What "incumbent" looks like — and where it breaks

Incumbent detection works well when:
- There's a single award (or small number) for the same NAICS at the same agency in the lookback window.
- One recipient holds the bulk of the obligation.

It breaks when:
- The agency uses **multiple-award IDIQs**: 5-15 prime contractors all hold the vehicle; "incumbent" is ambiguous.
- The work was **bundled or unbundled** between procurements (different NAICS, same scope, or vice versa).
- The previous procurement was **sole-source** and never appeared in SAM, so there's no notice to link to.
- The recipient was **acquired or renamed** between the prior award and the upcoming opportunity (UEI sometimes carries through; recipient name often doesn't).

The gem surfaces an incumbent when the signal is clean and returns `nil` otherwise. It does **not** force a guess. Downstream apps (like the Vindor scoring engine) layer their own confidence logic on top.

## Building a unified picture

The narrative the gem enables, in code:

```ruby
opp = Contractkit::Opportunity.find("FA8771-26-R-0042")

opp.agency             # normalized
opp.naics              # normalized
opp.related_awards     # who has done this work for this agency
opp.likely_incumbent   # the dominant recipient, if any
opp.related_awards.sum(&:obligated_amount)   # market size, lookback window
```

That's the whole point. Two API calls, one mental model. Neither SAM nor USASpending alone tells this story.

## Edge cases the gem deliberately doesn't handle (yet)

- **Grants** — USASpending exposes them; SAM doesn't. Out of scope (v1 is contracts only).
- **Subawards / sub-recipients** — different data quality story, often missing.
- **Classified procurements** — never appear in either API. Nothing to do here.
- **State and local procurement** — USASpending only covers federal. State equivalents are not in the gem's domain.
- **Same-day matching** — if a SAM award notice and a USASpending award appear on the same day, neither has propagated to the other yet. The gem currently treats them as independent.

## Open questions for the maintainer

> ⚠️ FILL IN: Is there a desired strategy for handling multiple-award IDIQs in `likely_incumbent`? Today it returns nil if no single recipient dominates; should it return an array of all award-holders instead?
>
> ⚠️ FILL IN: How aggressive should the default `ending_window` be? 24 months is the current proposal; the Rails app may already have a tuned value.
>
> ⚠️ FILL IN: Should the gem expose a confidence score for cross-references, or strictly leave that to consumers?
