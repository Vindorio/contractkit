# Data Models & Normalization

> **Purpose:** Define the gem's typed model objects — what they expose, how SAM.gov and USASpending.gov fields map into them, and how they handle the differences between the two upstream shapes.
>
> **Audience:** Contractkit contributors writing or reviewing model / parser code.

Related: [[sam-gov]], [[usaspending]], [[cross-referencing]], [[agency-normalization]], [[naics-and-setasides]], [[architecture-overview]]

---

## Design principles

1. **Plain Ruby objects.** No ActiveRecord, no ActiveModel, no Virtus. `attr_reader` + a constructor that takes a hash. Frozen after init where practical.
2. **Raw access is non-negotiable.** Every model exposes `.raw` (the original parsed JSON it was built from) and `.to_h` (the normalized hash form the gem promises). Callers who hit a gap can always drop down to `.raw` without forking the gem.
3. **Nil-safe everywhere.** Both APIs return inconsistent payloads. Missing fields return `nil`, never raise. Type coercion (`Date.parse`, `BigDecimal`) is wrapped so a malformed value also yields `nil` rather than crashing the iterator mid-page.
4. **Symmetry where it helps, divergence where it doesn't.** `naics_code`, `psc_code`, `set_aside_code`, `agency`, `place_of_performance` are shared value objects across `Opportunity` and `Award`. Monetary fields, dates, and lifecycle fields stay distinct — forcing them into a common shape would lie about the data.
5. **Value objects for things with semantics.** A NAICS code isn't a string; it's a 6-digit hierarchical classifier with a sector, subsector, and label. Same for PSC and set-asides. Strings are for things without behaviour.

---

## Model overview

| Model | Source | Identity field | Notes |
|---|---|---|---|
| `Contractkit::Opportunity` | SAM.gov | `notice_id` | One per SAM notice. Solicitations, sources-sought, awards — all of it. |
| `Contractkit::Award` | USASpending | `award_id` (`generated_unique_award_id`) | One per award, not per transaction. See [[usaspending]] §"Awards vs Transactions". |
| `Contractkit::Recipient` | USASpending | `uei` | Vendor identity. Built from inline award data or fetched standalone. |
| `Contractkit::Agency` | both | `code_path` (FPDS) | Normalized via lookup table; see [[agency-normalization]]. |
| `Contractkit::Naics` | both | `code` (6-char string) | Value object. Sector/subsector helpers. |
| `Contractkit::Psc` | both | `code` (4-char string) | Value object. |
| `Contractkit::SetAside` | both | `code` | Value object with `small_business?`, `socioeconomic?` predicates. |
| `Contractkit::PlaceOfPerformance` | both | n/a | Value object. Handles SAM's polymorphic state shape. |

---

## Cross-source field map

The 20-ish fields the gem normalizes across both sources. `—` means "not present in that source."

| Gem field | SAM (`Opportunity`) | USASpending (`Award`) | Type |
|---|---|---|---|
| `notice_id` | `noticeId` | — | `String` |
| `award_id` | — | `generated_unique_award_id` | `String` |
| `piid` | — | `Award ID` / `piid` | `String` |
| `parent_piid` | — | `parent_award_piid` | `String?` |
| `solicitation_number` | `solicitationNumber` | `piid` (fuzzy; see [[cross-referencing]]) | `String?` |
| `title` | `title` | — (use `description`) | `String` |
| `description` | `description` | `Description` | `String?` |
| `notice_type` | `type` | — | `String` |
| `notice_base_type` | `baseType` | — | `String` |
| `award_type` | — | `Award Type` | `String` |
| `agency` | `fullParentPathName` + `fullParentPathCode` | `Awarding Agency` + `Awarding Sub Agency` | `Agency` |
| `funding_agency` | — | `Funding Agency` | `Agency?` |
| `naics` | `naicsCode` | `naics_code` | `Naics` |
| `psc` | `classificationCode` | `psc_code` | `Psc?` |
| `set_aside` | `typeOfSetAside` + `…Description` | `Type of Set Aside` | `SetAside?` |
| `place_of_performance` | `placeOfPerformance` | `Place of Performance *` | `PlaceOfPerformance?` |
| `recipient` | `awardee` (award notices only) | `Recipient *` / `uei` | `Recipient?` |
| `posted_at` | `postedDate` | — | `DateTime` |
| `response_deadline_at` | `responseDeadLine` | — | `DateTime?` |
| `archive_at` | `archiveDate` | — | `Date?` |
| `period_start` | — | `Start Date` | `Date?` |
| `period_end` | — | `End Date` | `Date?` |
| `last_modified_at` | — | `Last Modified Date` | `DateTime?` |
| `obligated_amount` | `award.amount` (award notices) | `Award Amount` / `total_obligation` | `BigDecimal?` |
| `ceiling` | — | `Base + All Options Value` | `BigDecimal?` |
| `ceiling_exercised` | — | `Base + Exercised Options Value` | `BigDecimal?` |
| `contacts` | `pointOfContact` | — | `Array<Contact>` |
| `attachments` | `resourceLinks` | — | `Array<String>` |
| `links` | `links` | — | `Array<Hash>` |

> ⚠️ FILL IN: Confirm whether Vindor needs `total_outlays` exposed on `Award`. If yes, add a `outlaid_amount` field and document the lag semantics from [[usaspending]] §"Money fields".

---

## `Contractkit::Opportunity`

```ruby
module Contractkit
  class Opportunity
    attr_reader :notice_id, :title, :description,
                :solicitation_number,
                :notice_type, :notice_base_type,
                :agency,                  # Contractkit::Agency
                :naics,                   # Contractkit::Naics
                :psc,                     # Contractkit::Psc | nil
                :set_aside,               # Contractkit::SetAside | nil
                :place_of_performance,    # Contractkit::PlaceOfPerformance | nil
                :posted_at,               # DateTime
                :response_deadline_at,    # DateTime | nil
                :archive_at,              # Date | nil
                :contacts,                # Array<Contact>
                :attachments,             # Array<String>
                :links,                   # Array<Hash>
                :additional_info_url,     # String | nil
                :award,                   # Hash | nil (only on Award Notice type)
                :raw                      # Hash — original SAM payload

    def self.from_sam(hash); end          # builds + freezes
    def to_h; end                         # normalized hash, symbol keys
    def award_notice?; end                # type == "Award Notice"
    def solicitation?; end
    def related_awards(client: Contractkit.client, **opts); end
                                          # see [[cross-referencing]]
  end

  Contact = Struct.new(:full_name, :title, :email, :phone, :type, keyword_init: true)
end
```

### Non-obvious choices

- **`title` vs `description`.** SAM gives both; the gem keeps both. `title` is the short label; `description` is the long-form body and may be HTML — the gem does **not** strip HTML, that's a presentation concern.
- **`award` stays a hash, not a sub-object.** Only `Award Notice` types populate it, the shape is shallow, and joining to a real `Award` from USASpending is what `related_awards` is for. A sub-model would imply more guarantees than SAM actually provides.
- **`contacts` is always an array.** SAM sometimes returns a single object, sometimes an array, sometimes empty. Normalize to array on ingest.
- **No `state` enum / lifecycle machine.** [[sam-gov]] §"Notice types and lifecycle" explains why: notices are loosely sequential and a real procurement can fork/restart. Predicates (`award_notice?`, `solicitation?`) are enough.

---

## `Contractkit::Award`

```ruby
module Contractkit
  class Award
    attr_reader :award_id,                # String — generated_unique_award_id
                :piid,                    # String
                :parent_piid,             # String | nil
                :award_type,              # String
                :description,             # String | nil
                :agency,                  # Contractkit::Agency (awarding)
                :funding_agency,          # Contractkit::Agency | nil
                :recipient,               # Contractkit::Recipient
                :naics,                   # Contractkit::Naics
                :psc,                     # Contractkit::Psc | nil
                :set_aside,               # Contractkit::SetAside | nil
                :place_of_performance,    # Contractkit::PlaceOfPerformance | nil
                :obligated_amount,        # BigDecimal | nil
                :ceiling,                 # BigDecimal | nil
                :ceiling_exercised,       # BigDecimal | nil
                :period_start,            # Date | nil
                :period_end,              # Date | nil
                :last_modified_at,        # DateTime | nil
                :raw

    def self.from_usaspending(hash); end
    def to_h; end
    def idiq?; end                        # parent_piid present
    def expiring_within?(months);  end    # period_end within N months from today
    def related_opportunity(client: Contractkit.client, **opts); end
  end
end
```

### Award vs transaction

The gem's `Award` is an **award**, not a transaction. The `obligated_amount` is the sum of all transactions on this award to date (per [[usaspending]] §"Money fields"). Transaction-level fidelity is out of scope for v1 — callers who need it can use `.raw` and re-fetch `/awards/{id}/`.

### Money fields

Three monetary attributes, each wrapped to a `BigDecimal` (never `Float`):

- `obligated_amount` — money actually obligated. This is what most consumers want.
- `ceiling` — base + all options (the contract's maximum value).
- `ceiling_exercised` — base + options exercised so far.

The gem never returns `Float` for money. If parsing fails, the attribute is `nil`, never `0.0` (which would silently miscount in aggregations).

> ⚠️ FILL IN: Confirm whether Vindor's recompete-detection code needs `period_end` to include exercised options only, or all options. The semantics on USASpending's `End Date` shift depending on the award type.

---

## `Contractkit::Recipient`

```ruby
module Contractkit
  class Recipient
    attr_reader :uei,                     # String — 12-char primary key
                :duns,                    # String | nil — pre-2022 legacy
                :name,                    # String
                :parent_uei,              # String | nil
                :parent_name,             # String | nil
                :country_code,            # String | nil — ISO-2
                :state,                   # String | nil — 2-letter
                :business_types,          # Array<String> — small biz / 8(a) / etc.
                :raw

    def self.from_usaspending(hash); end
    def to_h; end
    def small_business?; end              # derived from business_types
  end
end
```

- **UEI is primary.** DUNS is exposed but soft-deprecated, matching [[usaspending]] §"Recipient UEI vs DUNS".
- **Names are not normalized.** USASpending shouts them (`"ACME CORPORATION"`); the gem preserves casing for fidelity. Callers who want title-case do it themselves.
- **`business_types`** is a flat array of strings (USASpending returns boolean-per-type, the gem flattens to just the truthy labels — easier to filter on).

---

## `Contractkit::Agency`

Agency is the messiest cross-source field. See [[agency-normalization]] for the full rationale; this section covers the model.

```ruby
module Contractkit
  class Agency
    attr_reader :code,      # String | nil — short identifier (e.g. "VA", "DOD", "GSA")
                :name,      # String — canonical full name; raw input on fallback
                :cgac,      # String | nil — 3-digit Treasury CGAC code (e.g. "036")
                :aliases    # Array<String> — known variant strings (frozen)

    def self.normalize(input); end  # 3-layer lookup; never raises, never nil
    def self.canonical(code); end   # known Agency for a code, or nil
    def self.all; end               # frozen array of shipped canonical agencies
    def to_h; end
    def ==(other); end              # equality by code when both have one, else by name
  end
end
```

### Normalization strategy

Three layers, in order, **no fuzzy match** (rejected — false-positive risk too high; "Department of Education" → "Department of Energy" is a real failure mode for any cheap string metric):

1. **Consumer-registered aliases** from `Contractkit.configure { |c| c.agency_aliases.merge!(...) }`. Takes precedence so consumers can patch in-process without waiting for a gem release.
2. **Shipped baseline table** at `lib/contractkit/data/agency_aliases.json`. v0.1 covers **~25 cabinet-level departments** (15 statutory cabinet departments + major independent agencies). Subtier coverage (service branches, components, offices) is v0.2.
3. **Raw-string fallback.** Returns `Agency.new(code: nil, name: <raw>, cgac: nil, aliases: [])`. Never raises. Consumers detect un-normalized cases by checking `agency.code.nil?`.

See [[agency-normalization]] for the full design rationale and the alias-table structure.

---

## Value objects

### `Contractkit::Naics`

NAICS is a value object, **not a string**. Justification:

- Codes have inherent hierarchy: digits 1-2 = sector, 1-3 = subsector, 1-4 = industry group, 1-5 = NAICS industry, 1-6 = national industry. Carrying that around as raw strings means every consumer reimplements `code[0,2]` slicing and looks up the sector label themselves.
- The gem ships a NAICS lookup table anyway (per architecture decision). Wrapping the string with that lookup is free.
- A value object lets us enforce the zero-padding fix from [[sam-gov]] §"`naicsCode` as integer" in exactly one place.

```ruby
module Contractkit
  class Naics
    attr_reader :code,                    # String — 6-char zero-padded
                :label                    # String — from lookup, e.g. "Custom Computer Programming Services"

    def self.coerce(value); end           # accepts String or Integer, normalizes
    def sector;     end                   # 2-char prefix
    def subsector;  end                   # 3-char prefix
    def industry_group; end               # 4-char prefix
    def sector_label;    end              # looked-up label for the 2-char prefix
    def to_s;       end                   # returns code
    def ==(other);  end                   # by code
    def hash; end                         # so it works as a Hash key
  end
end
```

### `Contractkit::Psc`

PSC = Product Service Code (4-char alphanumeric). Same reasoning as NAICS — hierarchical (first char = category) and looked up against a shipped table.

```ruby
module Contractkit
  class Psc
    attr_reader :code, :label
    def category;       end               # first char, e.g. "D" for "IT and Telecom"
    def category_label; end
    def product?;  end                    # numeric category → product
    def service?;  end                    # alpha category → service
    def to_s; end
  end
end
```

### `Contractkit::SetAside`

```ruby
module Contractkit
  class SetAside
    attr_reader :code,                    # String — e.g. "SBA", "8A", "SDVOSBC"
                :label                    # String — human-readable

    def small_business?;  end             # any SBA-flagged set-aside
    def socioeconomic?;   end             # 8(a), HUBZone, WOSB, SDVOSB, etc.
    def sole_source?;     end             # set-asides whose code ends in "S"
  end
end
```

The predicates are derived from a static classification table; see [[naics-and-setasides]].

### `Contractkit::PlaceOfPerformance`

Handles the polymorphism documented in [[sam-gov]] §"`placeOfPerformance.state` polymorphism".

```ruby
module Contractkit
  class PlaceOfPerformance
    attr_reader :city,                    # String | nil
                :state,                   # String | nil — 2-letter, always normalized
                :state_name,              # String | nil — full name when available
                :zip,                     # String | nil
                :country_code,            # String | nil — ISO-2
                :country_name,            # String | nil

    def self.from_sam(hash); end          # handles both string and {code,name} shapes
    def self.from_usaspending(hash); end
    def to_h; end
    def domestic?;  end                   # country_code in (nil, "US", "USA")
  end
end
```

---

## Cross-reference fields

The fields that make `opportunity.related_awards` and `award.related_opportunity` work. See [[cross-referencing]] for the full join logic; this is the minimum the data model has to surface.

| Join key | Reliability | Where it lives |
|---|---|---|
| **Agency code (FPDS)** + **NAICS code** | High (default match). | `agency.code` + `naics.code` on both sides. |
| **Recipient UEI** | High when populated. Award notices on SAM include it; pre-2022 awards have DUNS only. | `recipient.uei` on both. |
| **Solicitation number / PIID** | Low (~30-40% match rate; see [[sam-gov]]). | `solicitation_number` on `Opportunity`, `piid` on `Award`. |
| **Place of performance state** | Medium — useful as a tiebreaker, not a primary key. | `place_of_performance.state` on both. |

Default join (per architecture decision): **agency.code + naics.code**, with `recipient.uei` upgrading the match confidence when both sides have it. PIID/solicitation matching is opt-in via `match: :solicitation` because the false-negative rate is too high to default on.

> ⚠️ FILL IN: Vindor currently runs cross-referencing inside the Rails app — confirm the exact default join keys it uses today, and whether the gem should ship Vindor's defaults or stricter ones.

---

## `.raw` and `.to_h` contract

- **`.raw`** returns the upstream payload **for that single record**, parsed from JSON but otherwise unmodified. For `Opportunity`, that's one element of `opportunitiesData`. For `Award`, one element of `/search/spending_by_award/`'s `results`. Frozen.
- **`.to_h`** returns a symbol-keyed hash of the normalized fields documented above. Value objects are recursively `to_h`'d. Round-tripping `Opportunity.new(opp.to_h)` is **not** supported in v1 — `.to_h` is for inspection and serialization, not reconstruction.

> ⚠️ FILL IN: Should the gem support `Opportunity.from_h` for round-tripping in a future version? Useful for cache layers, but adds a versioning burden. Defer or commit?

---

## Open questions

> ⚠️ FILL IN: Equality semantics — should `Opportunity#==` compare by `notice_id` only, or by full content? Current lean: identity-only, since notices are mutable upstream.
>
> ⚠️ FILL IN: Memory budget — typed objects + frozen raw hash roughly doubles memory vs raw-hash-only. Confirm acceptable for Vindor's pipeline workloads (which historically pulled ~30 days × ~5k opps/day).
>
> ⚠️ FILL IN: Do we expose a `Transaction` model in v1, or wait until a real consumer needs it? Current lean: wait.
