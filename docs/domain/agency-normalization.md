# Agency Normalization

> **Purpose:** Why agency names are a mess across federal procurement data, and how the gem makes them tractable.
>
> **Audience:** Contractkit contributors; anyone debugging "why didn't this join work?" issues.

Related: [[sam-gov]], [[usaspending]], [[cross-referencing]]

---

## The problem in one paragraph

The federal government has no single canonical list of "what agencies exist and what they're called." SAM.gov, USASpending.gov, and FPDS each maintain overlapping but non-identical agency representations. The same agency can appear under three to six different spellings across these systems, and the differences are not always normalizable by simple uppercasing or whitespace stripping. Without a normalization layer, cross-system joins on agency silently miss 20-40% of matches.

## The hierarchy

Federal agencies are nested:

```
Department (top-tier)
  └── Sub-tier agency (a.k.a. component, bureau)
        └── Office (procurement office, contracting activity)
              └── (sometimes deeper: command, directorate, division)
```

Example for the Air Force:

```
Department of Defense
  └── Department of the Air Force
        └── Air Force Materiel Command
              └── Air Force Life Cycle Management Center (AFLCMC)
                    └── AFLCMC/HBA (specific contracting office)
```

The gem normalizes to **top-tier** by default. Sub-tier and office are exposed but treated as supplementary identifiers, not primary keys.

## How each system represents agencies

### SAM.gov

Exposes the full hierarchy in one field, dot-separated:

```
fullParentPathName: "DEPT OF DEFENSE.DEPT OF THE AIR FORCE.AFMC.AFLCMC"
fullParentPathCode: "9700.5700.FA8773.FA8771"
```

Also provides decomposed fields (`department`, `subTier`, `office`), but these don't always match the path exactly — case can differ, abbreviations can vary, and missing levels in the path may still appear in the decomposed fields.

**Quirks:**
- Heavy abbreviation: `DEPT OF` instead of `Department of`, `AFMC` instead of full name.
- ALL CAPS for the path; mixed case for the decomposed fields.
- The path can be 2-5 levels deep depending on the office.

### USASpending.gov

Uses two nested objects:

```json
"awarding_agency": {
  "toptier_agency": { "name": "Department of Defense", "code": "097" },
  "subtier_agency": { "name": "Department of the Air Force", "code": "5700" }
}
```

Office level is on the transaction record (`awarding_office_name`), not the award.

**Quirks:**
- Title case throughout (`Department of Defense`, not `DEPT OF DEFENSE`).
- Toptier codes are CGAC (3-digit Treasury); subtier codes are FPDS agency codes (4-digit).
- Funding agency vs awarding agency can differ — the gem defaults to awarding.

### FPDS

The system of record behind USASpending's contract data. Uses FPDS agency codes (4-digit alphanumeric). Codes are stable; names attached to codes have drifted over the years and are not authoritative.

## Common variants for the same agency

Department of Veterans Affairs:
- `VA`
- `Department of Veterans Affairs`
- `DEPARTMENT OF VETERANS AFFAIRS`
- `VETERANS AFFAIRS, DEPARTMENT OF`
- `DEPT OF VETERANS AFFAIRS`
- `Veterans Affairs, Department of`
- `VETERANS AFFAIRS`

Department of Defense:
- `DOD`
- `DoD`
- `Department of Defense`
- `DEPT OF DEFENSE`
- `DEPARTMENT OF DEFENSE`

Air Force (sub-tier under DoD):
- `Department of the Air Force`
- `DEPT OF THE AIR FORCE`
- `Air Force`
- `USAF`
- `DEPT OF AIR FORCE` (typo variant — appears in older SAM data)

> ⚠️ FILL IN: Add 5-10 more agency variant clusters you've actually hit. Pick agencies you do real business with — the long tail (NASA, DHS components, HHS components, civilian small agencies) is where the gem needs the most coverage.

## Available reference data

| Source | What it gives you | Useful? |
|---|---|---|
| CGAC codes (Treasury) | 3-digit toptier codes + names | Yes — authoritative for toptier identity. |
| FPDS agency codes | 4-digit sub-tier codes + names | Yes — authoritative for sub-tier identity. |
| USASpending `/agency/` | Full hierarchy with codes | Yes — best one-stop shop; mirrors FPDS/CGAC. |
| SAM `fullParentPathCode` | Hierarchical FPDS codes | Yes — the only reliable identifier inside SAM data. |
| OMB MAX agency list | Authoritative-ish federal list | Updated infrequently; useful as a baseline. |
| GSA Federal Agency Hierarchy | Cross-walks the above | Best cross-reference source. |

## The gem's normalization strategy

Three layers, in priority order:

### Layer 1: Code-based matching (preferred)

When both sides expose codes (CGAC or FPDS), match on codes. Codes are stable; names drift.

```
SAM      fullParentPathCode "9700.5700"     → toptier "097", subtier "5700"
USAsp    toptier_code "097", subtier "5700" → match
```

This handles 70-80% of cases cleanly. The gem ships a static lookup from FPDS codes → canonical agency names (snapshot taken at gem-release time; refreshable).

### Layer 2: Canonicalization table

For when only names are available (e.g. user-supplied agency filter strings), the gem ships an aliases table:

```ruby
Contractkit::Agency.normalize("VA")
# => #<Agency canonical:"Department of Veterans Affairs" toptier_code:"036">

Contractkit::Agency.normalize("VETERANS AFFAIRS, DEPARTMENT OF")
# => #<Agency canonical:"Department of Veterans Affairs" toptier_code:"036">
```

The table is curated, not exhaustive. It covers the top ~150 agencies (every cabinet department + every major sub-tier with >$1B in annual procurement). Long-tail agencies fall through to layer 3.

### Layer 3: Fuzzy fallback

If neither code nor table match, the gem applies normalized string comparison:
1. Uppercase.
2. Strip punctuation.
3. Strip filler words (`DEPARTMENT`, `DEPT`, `OF`, `THE`, `,`).
4. Compare against the canonical table's same-treated names.

This catches near-misses like `DEPT OF AIR FORCE` vs `DEPARTMENT OF THE AIR FORCE` but is deliberately conservative — it returns a match only above a high similarity threshold, and never silently coerces ambiguous matches.

### Override hook

Because the table goes stale (agency reorganizations, new sub-tiers, renames), it must be patchable in-process:

```ruby
Contractkit::Agency.register_alias(
  "SOME NEW NAME WE HAVENT SHIPPED YET",
  canonical: "Department of Whatever",
  toptier_code: "012"
)
```

This is the contract with downstream consumers: the gem ships a good baseline, never claims to be exhaustive, and exposes a clean hook to add what we missed without monkey-patching.

## What we deliberately don't try to do

- **Office-level normalization.** The data is too noisy. The gem normalizes to sub-tier; office is exposed but untouched.
- **Fuzzy-match by Levenshtein on full agency names.** False positives are too dangerous (matching "Department of Education" to "Department of Energy" is a real risk). The aliases table is curated; fuzzy fallback is only over the filler-word-stripped form.
- **Handle inter-agency transfers.** If money was awarded by Treasury on behalf of HHS, both fields exist and the gem keeps both — it does not pick one.

## Open questions for the maintainer

> ⚠️ FILL IN: What's the freshness policy for the shipped aliases table? Re-snapshot every minor release? Every year?
>
> ⚠️ FILL IN: Should the gem expose `awarding_agency` vs `funding_agency` distinctly on the `Award` model, or collapse to a single `agency`? Today's proposal: both, with `agency` aliased to awarding.
>
> ⚠️ FILL IN: Are there agencies the Vindor business cares about that aren't in the top-150 baseline? List them so the table covers them on day one.
