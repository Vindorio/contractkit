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

Three lookup layers, checked in priority order. **No fuzzy matching in v0.1** — fuzzy match was considered and rejected because the false-positive risk (matching "Department of Education" to "Department of Energy") outweighed the benefit. Exact lookup against a curated alias table is the entire mechanism.

The `Agency` value object exposes four readers:

- `code` — short identifier used by consumers for indexed storage (e.g. `"VA"`, `"DOD"`, `"GSA"`)
- `name` — canonical full name (e.g. `"Department of Veterans Affairs"`)
- `cgac` — 3-digit Treasury CGAC code (e.g. `"036"`)
- `aliases` — frozen array of known variant strings that resolve to this canonical form (informational)

### Layer 1: Consumer-registered aliases (highest priority)

Aliases registered via `config.agency_aliases` take precedence. This is the consumer escape hatch — when the gem's shipped table misses an agency the consumer cares about, the consumer patches it in-process:

```ruby
Contractkit.configure do |config|
  config.agency_aliases.merge!(
    "NAVAL SEA SYSTEMS COMMAND" => "DOD-NAVY",
    "USACE"                     => "DOD-ARMY"
  )
end
```

Consumer aliases pointing at an unknown code don't raise; they produce an `Agency` with `code: nil` and the registered name.

### Layer 2: Shipped baseline table

`lib/contractkit/data/agency_aliases.json`, hand-curated. v0.1 covers the **~25 cabinet-level departments** — the 15 statutory cabinet departments plus the major independent agencies that procure heavily (GSA, NASA, EPA, SBA, USAID, NSF, SSA, OPM, NRC, USPS). Each entry lists 5-10 known variant strings observed in real SAM and USASpending payloads.

Subtier coverage (DoD service branches, DHS components, contracting offices) is **deferred to v0.2**. In v0.1, an opportunity awarded by "Department of the Air Force" still normalizes — via the aliases for `"DOD"` — but loses the Air-Force-specific signal until v0.2 introduces subtier entries.

### Layer 3: Raw-string fallback

If neither layer 1 nor layer 2 matches, the gem returns an `Agency` with `code: nil`, `name: <raw input>`, `cgac: nil`, `aliases: []`. **Never raises, never returns `nil`.** Consumers detect un-normalized cases by checking `agency.code.nil?` and either ship a fix back to the gem or register a local alias.

```ruby
Contractkit::Agency.normalize("VA")
# => #<Agency code:"VA" name:"Department of Veterans Affairs" cgac:"036" aliases:[...]>

Contractkit::Agency.normalize("VETERANS AFFAIRS, DEPARTMENT OF")
# => #<Agency code:"VA" name:"Department of Veterans Affairs" cgac:"036" aliases:[...]>

Contractkit::Agency.normalize("ZZZ UNKNOWN INDEPENDENT THING")
# => #<Agency code:nil name:"ZZZ UNKNOWN INDEPENDENT THING" cgac:nil aliases:[]>
```

This is the contract with downstream consumers: the gem ships a small, curated baseline, never claims to be exhaustive, and exposes a clean hook to add what we missed without monkey-patching.

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
