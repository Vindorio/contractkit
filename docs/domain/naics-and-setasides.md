# NAICS Codes and Set-Aside Types

> **Purpose:** Reference for the two classification systems that drive eligibility and matching in federal procurement: NAICS codes and set-aside types. Both are hard gates in real procurements, not soft signals.
>
> **Audience:** Contractkit contributors; anyone reasoning about who can bid on what.

Related: [[sam-gov]], [[usaspending]], [[cross-referencing]]

---

## NAICS — North American Industry Classification System

### What it is

NAICS is the federal government's industry taxonomy. Every procurement is assigned exactly one NAICS code that describes the kind of work being bought (IT services, construction, medical equipment, etc.). The code determines which firms are eligible to bid under small-business set-asides, because each NAICS has a size standard attached (revenue or employee-count threshold below which a firm counts as "small").

NAICS is **not** marketing taxonomy. It's a regulated eligibility filter. A firm bidding under the wrong NAICS can have its proposal eliminated for non-responsiveness.

### Structure

NAICS codes are 2-6 digits, hierarchical:

| Digits | Level | Example |
|---|---|---|
| 2 | Sector | `54` — Professional, Scientific, and Technical Services |
| 3 | Subsector | `541` — Professional, Scientific, and Technical Services (narrower) |
| 4 | Industry Group | `5415` — Computer Systems Design and Related Services |
| 5 | NAICS Industry | `54151` — Computer Systems Design and Related Services |
| 6 | National Industry | `541512` — Computer Systems Design Services |

Federal procurement always uses the **6-digit** form. SAM and USASpending both store the 6-digit code.

### Versions

NAICS is updated every 5 years. Recent versions:

- NAICS 2017
- NAICS 2022 (current as of gem v1)
- NAICS 2027 (next; not yet published)

> ⚠️ FILL IN: Confirm whether SAM and USASpending have both moved to NAICS 2022, or whether either system still ships some records under NAICS 2017 codes that no longer exist. Edge cases matter here.

Codes can be added, removed, or split between versions. A handful of 2017 codes don't exist in 2022 (and vice versa). The gem ships a single version snapshot; consumers needing historical accuracy should treat NAICS as approximate for awards >5 years old.

### Field representation

| Source | Field | Notes |
|---|---|---|
| SAM | `naicsCode` | Usually a 6-digit string; occasionally returned as an integer (loses leading zeros). Normalize to 6-char zero-padded string. |
| USASpending | `naics_code` | Always a 6-digit string. |
| Gem | `naics_code` (string) + `Naics` value object | Always 6-char zero-padded. The value object exposes sector/subsector/industry-group helpers. |

### Useful helpers

```ruby
n = Contractkit::Naics.lookup("541512")
n.code           # => "541512"
n.title          # => "Computer Systems Design Services"
n.sector_code    # => "54"
n.sector_title   # => "Professional, Scientific, and Technical Services"
n.subsector_code # => "541"
```

The lookup table is shipped with the gem as static data (~1100 entries). No network call.

### NAICS as an eligibility gate, not a category

A common consumer mistake: treating NAICS as a marketing label and pulling "all opportunities tagged 541512" expecting that to capture all the IT-services work a firm could bid. It does not. Agencies make discretionary calls about which NAICS to assign, and the assignment is binding for set-aside eligibility but not always for scope. A firm whose primary NAICS is 541511 may still be eligible (and competitive) on a 541512 opportunity — but only if the size standard at 541512 permits, and only if the firm's past performance covers the scope.

For the gem: never collapse "related" NAICS automatically. Surface the code; let the consumer decide.

## Set-Aside Types

### What they are

A set-aside reserves a procurement for a specific category of small business. Set-asides are statutory programs that exclude all firms not in the named category. Bidding outside your set-aside category gets you eliminated; bidding when there's a set-aside in effect that you don't qualify for gets you eliminated.

The major programs:

| Program | Who qualifies | Common codes |
|---|---|---|
| Small Business (SBA) | Firms below the NAICS size standard | `SBA`, `SBP` (partial) |
| 8(a) Business Development | SBA-certified disadvantaged small biz | `8A`, `8AN` (sole-source) |
| HUBZone | Firms in Historically Underutilized Business Zones | `HZS` (set-aside), `HZC` (sole-source) |
| SDVOSB | Service-Disabled Veteran-Owned Small Business | `SDVOSBS`, `SDVOSBC` (sole-source) |
| VOSB | Veteran-Owned Small Business (VA only, mostly) | `VSA`, `VSS` |
| WOSB | Women-Owned Small Business | `WOSB`, `WOSBSS` |
| EDWOSB | Economically Disadvantaged WOSB | `EDWOSB`, `EDWOSBSS` |
| Indian Economic Enterprise | BIA program | `IEE`, `BICiv` |
| Indian Small Business Economic Enterprise | Smaller subset of IEE | `ISBEE` |
| Local Area Set-Aside | Geographic recovery zones | `LAS`, `RP` |
| Full and open | No set-aside | `NONE` or blank |

> ⚠️ FILL IN: Confirm the canonical codes against the latest FAR / SAM controlled vocabulary. The above list is accurate to 2025 but the encoding has shifted historically.

### How set-aside codes appear

| Source | Field(s) | Notes |
|---|---|---|
| SAM | `typeOfSetAside` (code) + `typeOfSetAsideDescription` (label) | Both are usually populated, occasionally only one. |
| USASpending | `type_set_aside` | Code only; no description field. |
| Gem | `set_aside_code` (Symbol) + `set_aside_label` (String) | Normalized symbol form. |

### Normalized symbols

The gem exposes set-asides as Ruby symbols for ergonomics:

```ruby
Contractkit::SetAside.normalize("8A")        # => :sba_8a
Contractkit::SetAside.normalize("HZC")       # => :hubzone_sole_source
Contractkit::SetAside.normalize("SDVOSBS")   # => :sdvosb
Contractkit::SetAside.normalize("WOSBSS")    # => :wosb_sole_source
Contractkit::SetAside.normalize("")          # => :none
Contractkit::SetAside.normalize("NONE")      # => :none

Contractkit::SetAside.label(:sba_8a)
# => "8(a) Business Development Program"

Contractkit::SetAside.label(:sdvosb)
# => "Service-Disabled Veteran-Owned Small Business"
```

### Exact match vs category match

Set-asides do not compose. An opportunity set aside for SDVOSB is **not** open to other small businesses, even smaller ones. A `:sba_8a` set-aside is not satisfied by being WOSB-certified. Matching must be exact on the program.

**Exception:** the partial set-aside (`:sba_partial` and a couple of similar codes) carves out a subset of work for small business while keeping the rest open. The gem exposes these but does not try to reason about the carve-out split.

## PSC — Product and Service Codes

### What they are

PSC is the federal government's product/service taxonomy, complementary to NAICS. Where NAICS describes the industry doing the work, PSC describes what's being bought. The same NAICS can map to many PSCs and vice versa.

### Structure

4-character alphanumeric. First character is a coarse category:

| Prefix | Category |
|---|---|
| `A` | R&D |
| `B` | Special studies and analyses (non-R&D) |
| `D` | IT and Telecom |
| `M` | Operation of Government-owned facilities |
| `Q` | Medical services |
| `R` | Professional services |
| `S` | Utilities, housekeeping |
| `T` | Photographic, mapping, printing, publication |
| `U` | Education and training |
| `V` | Transportation, travel, relocation |
| `1`-`9` | Goods (supplies/equipment) |

Subsequent characters narrow the category (`D316` is IT/cybersecurity, `R425` is engineering and tech management support).

### How PSCs appear

| Source | Field | Notes |
|---|---|---|
| SAM | `classificationCode` | Yes, the misleading name. It's the PSC. |
| USASpending | `psc_code` | Sane name. |
| Gem | `psc_code` (string) + `Psc` value object | The value object exposes the prefix category and the full label. |

### Does the gem use PSC?

Yes, but as a tightener, not a primary identifier:

- Lookup: `Contractkit::Psc.lookup("D316")`.
- Cross-reference: `opp.related_awards(match: [:agency, :naics, :psc])` opts into PSC-as-additional-constraint matching.

PSC lookup table is shipped as static data (~5000 entries).

## Open questions for the maintainer

> ⚠️ FILL IN: Is the gem shipping a full PSC table or just the first character (category)? Decide and document.
>
> ⚠️ FILL IN: How does the gem handle NAICS 2017 codes that don't exist in NAICS 2022? Soft-warn? Silently retain the raw string?
>
> ⚠️ FILL IN: Add edge cases for set-aside encoding you've actually hit (e.g. agencies that put the description in the code field, or vice versa).
