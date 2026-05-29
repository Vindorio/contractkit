# contractkit

> **Federal procurement data for Ruby.** Aggregates SAM.gov contract
> opportunities and USASpending.gov award history into a single,
> framework-agnostic gem with typed model objects, transparent
> pagination, opportunity-to-award cross-referencing, recompete
> detection, IDV tracking, and built-in rate-limit / retry /
> redaction middleware.

[![Status](https://img.shields.io/badge/status-pre--alpha-orange)](#status)

---

## For AI Agents

This section is designed to be parseable by LLM-based coding agents
(Claude, Codex, Copilot, etc.) for quick orientation.

**Project type:** Ruby gem (no Rails dependency)
**Ruby floor:** 3.2+
**Key dependency:** `faraday ~> 2.0` + `faraday-retry ~> 2.0`
**Test framework:** RSpec + VCR cassettes + WebMock (no network in CI)
**Linter:** RuboCop

**Entry point:** `lib/contractkit.rb` → `Contractkit.configure { |c| ... }`

**Two data sources:**
1. **SAM.gov** (`lib/contractkit/sam/`) — active contract opportunities
2. **USASpending.gov** (`lib/contractkit/usaspending/`) — historical awards

**Query pattern:** `Contractkit::Resource.search(params).first(n)` —
returns typed model objects. Lazy pagination. Always read `.raw` for
fields the gem doesn't surface.

**Resource modules and what they query:**

| Module | Source | Returns | Key method |
|---|---|---|---|
| `Contractkit::Opportunity` | SAM.gov | `Opportunity` | `.search`, `.find`, `.modified_since` |
| `Contractkit::Award` | USASpending | `Award` | `.search`, `.updated_since` |
| `Contractkit::Idv` | USASpending | `Idv` | `.search` |
| `Contractkit::Transaction` | USASpending | `Transaction` | `.for_award` |
| `Contractkit::Subaward` | USASpending | `Subaward` | `.for_award` |
| `Contractkit::Recipient` | USASpending + SAM | `Recipient` | `.find`, `.find_entity` |
| `Contractkit::CrossReference` | both | joins | `.awards_for`, `.likely_incumbent` |
| `Contractkit::Recompete` | both | joins | `.expiring(within:)` |

**Normalized lookup tables** (read-only, frozen at load):
`Agency.normalize(input)`, `Naics.lookup(code)`, `Psc.lookup(code)`,
`SetAside.normalize(input)`

**Files to read first:**
- `docs/contributing/architecture-overview.md` — mental model
- `docs/design/data-flow.md` — data flow Mermaid diagram
- `docs/domain/sam-gov.md` — SAM quirks you'll hit in production
- `docs/domain/usaspending.md` — USASpending quirks

---

## Status

**0.1.0 release candidate.** Pre-alpha. Private repo; will flip to
public under MIT once the gem is published to rubygems.org and the
docs have a cleanup pass.

API may change in 0.x without ceremony; we'll be conservative once we
hit 1.0. See [CHANGELOG.md](CHANGELOG.md) for the version history and
breaking-change policy.

## Why this exists

SAM.gov and USASpending.gov are run by different agencies with different
schemas, different auth, different pagination, undocumented rate limits,
and no shared identifier for the same procurement across both. Every
Ruby team that wants federal contract data ends up writing the same
HTTP plumbing, date-format conversions, agency-name normalization, and
recompete-detection joins.

Existing options:

- **Roll your own with `Net::HTTP`** — months of work; you'll re-discover
  every quirk listed in [`docs/domain/sam-gov.md`](docs/domain/sam-gov.md).
- **`pysam`** — Python, SAM-only, 14 stars.
- **Commercial scrapers** — expensive, redistribution-restricted.
- **USASpending's own Django backend** — designed as a hosted service,
  not a library.

`contractkit` is the missing piece: a small Ruby library that hides the
plumbing and surfaces clean object models, with the cross-reference
join that makes the data actually useful.

## Architecture

```
                              ┌─────────────────────┐
                              │   Your Ruby App      │
                              └──────────┬──────────┘
                                         │
                              ┌──────────▼──────────┐
                              │  Contractkit.configure│
                              │  or Client.new(...)  │
                              └─────┬─────────┬─────┘
                                    │         │
                          ┌─────────▼──┐  ┌───▼──────────┐
                          │ SAM Client │  │ USASpending   │
                          │ (GET + key)│  │ Client (POST) │
                          └─────┬──────┘  └───┬───────────┘
                                │             │
                          ┌─────▼──────┐  ┌───▼───────────┐
                          │    SAM.gov │  │ USASpending.gov│
                          │  /v2/search│  │ /spending_by   │
                          │            │  │ _award + more  │
                          └─────┬──────┘  └───┬───────────┘
                                │             │
                    ┌───────────▼──┐  ┌───────▼───────────┐
                    │ Response     │  │ Response          │
                    │ Parser (SAM) │  │ Parser (USASpend) │
                    └──────┬───────┘  └───────┬───────────┘
                           │                  │
                    ┌──────▼──────────────────▼──────┐
                    │   Typed Model Objects          │
                    │   Opportunity, Award, Idv,     │
                    │   Transaction, Subaward,       │
                    │   Recipient, Agency, ...       │
                    └──────────────┬─────────────────┘
                                   │
                    ┌──────────────▼─────────────────┐
                    │  CrossReference / Recompete    │
                    │  (cross-source joins)          │
                    └────────────────────────────────┘
```

**Middleware stack** (every request flows through, in order):
cache → rate limiter → retry → instrumentation → logger → Faraday adapter

## Install

```ruby
# Gemfile
gem "contractkit"
```

Then:

```bash
bundle install
```

Requires Ruby **3.2+**. Get a SAM.gov API key (free) at
[api.data.gov/signup](https://api.data.gov/signup/). USASpending is
keyless.

## Quick Start

```ruby
require "contractkit"

Contractkit.configure do |c|
  c.sam_api_key = ENV.fetch("SAM_API_KEY")
end

# Find recent IT-services opportunities for a NAICS code,
# identify likely incumbents from USASpending award history.
Contractkit::Opportunity.search(
  ncode: "541512",
  postedFrom: Date.today - 30,
  postedTo:   Date.today
).first(10).each do |opp|
  incumbent = opp.likely_incumbent
  puts "#{opp.title.slice(0, 60)}"
  puts "  agency:    #{opp.agency.code} (#{opp.agency.name})"
  puts "  set-aside: #{opp.set_aside}"
  puts "  incumbent: #{incumbent ? incumbent.name : '(none clear)'}"
end
```

For a fuller end-to-end script see
[`examples/find_recompetes.rb`](examples/find_recompetes.rb).

## Data Model Reference

### SAM.gov → `Contractkit::Opportunity`

| Field | Type | Description |
|---|---|---|
| `notice_id` | `String` | SAM unique identifier |
| `title` | `String` | Notice title |
| `solicitation_number` | `String?` | Solicitation number (format varies by agency) |
| `agency` | `Agency` | Canonical agency (normalized) |
| `posted_at` | `DateTime` | When posted to SAM |
| `response_deadline_at` | `DateTime?` | Proposal deadline |
| `archive_at` | `Date?` | Archive date |
| `notice_type` | `String` | "Solicitation", "Award Notice", etc. |
| `notice_base_type` | `String` | Coarser grouping |
| `naics_code` | `String` | 6-char zero-padded NAICS |
| `psc_code` | `String?` | 4-char PSC |
| `set_aside_code` | `String?` | Raw SAM code ("8A", "SDVOSBC", etc.) |
| `set_aside` | `Symbol` | Normalized (`:sba_8a`, `:sdvosb`, etc.) |
| `set_aside_label` | `String?` | Human label |
| `place_of_performance` | `PlaceOfPerformance?` | State/city/zip |
| `contacts` | `Array<Hash>` | POCs |
| `description` | `String?` | Full description (may contain HTML) |
| `additional_info_url` | `String?` | External link |
| `links` | `Array<Hash>` | HATEOAS links |
| `attachments` | `Array<String>` | Attachment URLs |
| `award` | `Hash?` | Populated on Award Notices only |
| `raw` | `Hash` | Original SAM JSON |

### USASpending → `Contractkit::Award`

| Field | Type | Description |
|---|---|---|
| `award_id` | `String` | `generated_unique_award_id` |
| `piid` | `String?` | Procurement instrument ID |
| `parent_piid` | `String?` | For IDIQ task orders |
| `award_type` | `String?` | "Definitive Contract", "BPA Call", etc. |
| `obligated_amount` | `BigDecimal?` | Money obligated to date |
| `ceiling` | `BigDecimal?` | Base + All Options |
| `total_contract_value` | `BigDecimal?` | Ceiling alias |
| `base_and_exercised_options_value` | `BigDecimal?` | Base + exercised options |
| `base_and_all_options_value` | `BigDecimal?` | Full ceiling |
| `total_obligation` | `BigDecimal?` | Sum of all transactions |
| `number_of_offers_received` | `Integer?` | Detail-only |
| `extent_competed` | `CodedValue?` | Detail-only (e.g. "A" = Full/Open) |
| `type_of_contract_pricing` | `CodedValue?` | Detail-only |
| `contract_award_type` | `CodedValue?` | Detail-only |
| `solicitation_procedures` | `CodedValue?` | Detail-only |
| `recipient` | `Recipient?` | Vendor identity |
| `awarding_agency` | `Agency?` | Who awarded it |
| `awarding_subagency_name` | `String?` | Sub-tier name |
| `funding_agency` | `Agency?` | Who funded it (may differ) |
| `naics_code` | `String?` | 6-char |
| `psc_code` | `String?` | 4-char |
| `set_aside_code` | `String?` | Raw code |
| `set_aside` | `Symbol` | Normalized |
| `period` | `Period?` | `{start_date, end_date}` as `Date` |
| `place_of_performance` | `PlaceOfPerformance?` | Location |
| `description` | `String?` | Free-text |
| `last_modified_at` | `DateTime?` | USASpending refresh time |
| `raw` | `Hash` | Original USASpending JSON |

### USASpending → `Contractkit::Idv` (Indefinite-Delivery Vehicle)

Separate class from Award. IDVs are umbrella contracts (IDC, GWAC, BPA,
BOA, FSS) under which task/delivery orders are placed.

Key fields: `piid`, `award_type`, `last_date_to_order` (primary recompete
signal), `period_end_date`. Has `#child_awards`, `#transactions`,
`#subawards` lazy-fetch methods.

See [`docs/domain/idvs.md`](docs/domain/idvs.md).

### USASpending → `Contractkit::Transaction`

Per-modification history. `Award#transactions` and `Idv#transactions`
lazy-fetch the modification stream. Key fields: `modification_number`,
`action_date`, `federal_action_obligation` (per-mod delta),
`action_type` (`CodedValue`).

See [`docs/domain/transactions.md`](docs/domain/transactions.md).

### USASpending → `Contractkit::Subaward`

One-level prime → sub teaming. `Award#subawards` and `Idv#subawards`
lazy-fetch. Both sides denormalized on the row
(`prime_recipient_uei`, `sub_recipient_uei`).

See [`docs/domain/subawards.md`](docs/domain/subawards.md).

### SAM → `Contractkit::Recipient` (enriched)

Two construction paths:
- **Un-enriched** from `Award.search` → name, uei, duns only
- **Enriched** via `Recipient.find_entity(uei)` → full SAM registration:
  `cage_code`, `registration_status`, `sam_expiration_date`,
  `business_types`, `sba_business_types`, `naics_list`,
  `exclusion_status_flag`, `immediate_owner`, `highest_owner`,
  predicates `#excluded?` and `#registration_expired?`

See [`docs/domain/entities.md`](docs/domain/entities.md).

### Value objects

| Class | Purpose | Key methods |
|---|---|---|
| `Agency` | Canonical agency reference | `.normalize(input)`, `.code`, `.name`, `.cgac` |
| `Naics` | NAICS code + hierarchy | `.lookup(code)`, `sector`, `subsector`, `label` |
| `Psc` | Product Service Code | `.lookup(code)`, `category`, `category_label` |
| `SetAside` | Set-aside type | `.normalize(input)`, `.label(sym)`, `.code(sym)`, predicates |
| `PlaceOfPerformance` | Location | `.state`, `.city`, `.zip`, `.country_code`, `#domestic?` |
| `Period` | Date range | `.start_date`, `.end_date` (both `Date`) |
| `CodedValue` | `(code, description)` pair | `.code`, `.description` |
| `OwnerReference` | SAM corporate owner | `.uei`, `.name`, `.cage_code` |

## Features

### Batch pagination

`#search` is record-level by default — `.first(n)` / `.each` /
`.take` yield individual model objects. For bulk pipelines, the same
result handle exposes `#each_batch`, which yields one array per
upstream API page (default 1000 for SAM, 100 for USASpending) so
memory cost stays at one page at a time, never accumulated.

```ruby
# Record-level (default)
Contractkit::Opportunity.search(ncode: "541512").first(50).each do |opp|
  process(opp)
end

# Batch interface (bulk pipelines)
Contractkit::Opportunity.search(ncode: "541512").each_batch do |batch|
  Contract.upsert_batch(batch.map(&:to_h))   # ~1000 records per batch
end

# Cap total records across all batches
Contractkit::Award.search(filters: { naics_codes: ["541512"] }, limit: 500)
```

### Typed model objects with `.raw` escape hatch

Every API response is parsed into a frozen value object with documented
readers. Money is `BigDecimal`. Dates are `Date` (not DateTime).
Recipients have UEIs. Agencies are normalized canonical instances. If
you need a field the gem doesn't surface, call `.raw` to get the
original API JSON.

```ruby
opp = Contractkit::Opportunity.search(ncode: "541512").first
opp.notice_id            # => "abc-123"
opp.naics_code           # => "541512" (always zero-padded 6 chars)
opp.set_aside            # => :sba_8a (Ruby symbol)
opp.set_aside_code       # => "8A"    (raw SAM code, source of truth)
opp.set_aside_label      # => "8(a) Set-Aside"
opp.posted_at            # => #<DateTime ...>
opp.agency.code          # => "DOD"
opp.agency.name          # => "Department of Defense"
opp.agency.cgac          # => "097"
opp.place_of_performance.state  # => "VA" (normalized from SAM's two-shape field)
opp.raw                  # => { ...original SAM JSON... }

award = Contractkit::Award.search(filters: { naics_codes: ["541512"] }).first
award.obligated_amount   # => BigDecimal("4250000.00")  (cent-precision)
award.ceiling            # => BigDecimal("12500000.00") (separate from obligated)
award.recipient.uei      # => "ABC123XYZ456"
award.period.start_date  # => #<Date 2026-03-15>
award.awarding_agency.code  # => "DOD"
```

### Agency normalization at ingestion

SAM and USASpending represent the same agency under wildly different
strings — "VA", "VETERANS AFFAIRS, DEPARTMENT OF", "Department of
Veterans Affairs". `contractkit` resolves all of these to a canonical
`Agency` value object at parse time, so consumers can store
`agency.code` ("VA") on their own models and run indexed queries
instead of fuzzy string matching.

```ruby
Contractkit::Agency.normalize("VA").code                              # => "VA"
Contractkit::Agency.normalize("VETERANS AFFAIRS, DEPARTMENT OF").code # => "VA"
Contractkit::Agency.normalize("Department of Veterans Affairs").code  # => "VA"
Contractkit::Agency.normalize("Some Made-Up Thing").code              # => nil
                                                                      #    (raw-string fallback; never raises)

# Extend with consumer-specific aliases
Contractkit.configure do |c|
  c.agency_aliases.merge!(
    "NAVAL SEA SYSTEMS COMMAND" => "DOD-NAVY",
    "USACE"                     => "DOD-ARMY"
  )
end
```

v0.1 ships ~25 cabinet-level departments (15 statutory cabinet + 10
major independents — GSA, NASA, EPA, SBA, USAID, NSF, SSA, OPM, NRC,
USPS). Sub-tier coverage is v0.2.

### Set-aside normalization (SAM codes as source of truth)

`opportunity.set_aside_code` carries the raw SAM code (`"8A"`,
`"SDVOSBC"`, `"WOSB"`). `opportunity.set_aside` carries the same value
as a Ruby symbol (`:sba_8a`, `:sdvosb_sole_source`, `:wosb`).
`opportunity.set_aside_label` is the canonical human label.

```ruby
Contractkit::SetAside.normalize("8A")         # => :sba_8a
Contractkit::SetAside.normalize("WOSBSS")     # => :wosb_sole_source
Contractkit::SetAside.normalize("Service-Disabled Veteran-Owned Small Business")
                                              # => :sdvosb
Contractkit::SetAside.label(:sba_8a)          # => "8(a) Set-Aside"
Contractkit::SetAside.code(:sba_8a)           # => "8A"
```

Nil/empty input maps to `:none` (full and open). Unknown input raises
`Contractkit::SetAside::UnknownCode` (subclass of `Contractkit::Error`,
not `ArgumentError`).

### Cross-reference: opportunities → related awards → likely incumbent

The flagship feature. SAM tells you about upcoming work; USASpending
tells you who's done similar work before. The gem joins them.

```ruby
opp = Contractkit::Opportunity.search(ncode: "541512").first

# Awards likely related to this opportunity (default: agency + NAICS match,
# 5-year lookback, capped at 50)
related = opp.related_awards
related.first.recipient.name      # => likely incumbent or competitor
related.first.obligated_amount    # => BigDecimal(...)

# Tune the match
opp.related_awards(
  match: [:agency, :naics, :psc],   # add PSC as a tightener
  lookback: 3,                       # years
  limit: 100
)

# Dominant-recipient heuristic (>50% of obligation across related awards)
opp.likely_incumbent              # => Contractkit::Recipient or nil

# When the field is split across multiple award-holders (multi-award IDIQ)
# this returns nil — the gem doesn't force a guess.
```

### Recompete detection (time-forward)

New in M4. `Contractkit::Recompete.expiring(within:)` pairs expiring
IDVs and contracts with active SAM solicitations that might be their
follow-on.

```ruby
# Find all IDVs/contracts expiring in the next 12 months, each paired
# with matching SAM opportunities:
Contractkit::Recompete.expiring(within: 12) do |match|
  puts "#{match.award.piid} expires, #{match.matching_opportunities.size} matches"
end

# As Enumerator:
Contractkit::Recompete.expiring(within: 6, naics: "541512").first(10)
```

See [`docs/domain/recompete.md`](docs/domain/recompete.md).

### Entity enrichment (SAM registration data)

New in M4. Enrich a USASpending-derived `Recipient` with full SAM
Entity Management data:

```ruby
award = Contractkit::Award.search(...).first
sam = Contractkit::Recipient.find_entity(award.recipient.uei)
sam.cage_code                     # => "12345"
sam.registration_status           # => "Active"
sam.excluded?                     # => false
sam.business_types.first.code     # => "2X" (For Profit Organization)
sam.sba_business_types.first.code # => "A6" (8(a))
```

See [`docs/domain/entities.md`](docs/domain/entities.md).

### Configuration

Every option, with its default:

```ruby
Contractkit.configure do |c|
  c.sam_api_key   = ENV.fetch("SAM_API_KEY")  # reads from env by default
  c.user_agent    = "contractkit/0.1.0 (+https://github.com/...)"
  c.timeout       = 30                         # read timeout (seconds)
  c.retries       = 3                          # 5xx + network errors only
  c.logger        = Rails.logger               # any Logger-shaped object
  c.cache         = Rails.cache                # any #read/#write object; nil = off
  c.cache_ttl     = 3600
  c.agency_aliases.merge!("..." => "...")      # consumer overrides
  c.on_event do |name, payload|                # instrumentation hook
    MyApp::Telemetry.track(name, payload)
  end
end
```

Multi-tenant consumers use instance-scoped clients instead:

```ruby
client = Contractkit::Client.new(
  sam_api_key: tenant.sam_key,
  timeout: 15
)
# ... client.configuration is fully isolated from Contractkit.configuration
```

### Reliability layer

Built in, no configuration required:

- **Rate limiter** — per-host token bucket; SAM 20 req/min, USASpending
  5 req/sec by default; blocks when bucket is empty; honors `Retry-After`
  on 429.
- **Retries** — exponential backoff with jitter on 5xx and network
  errors; never on 4xx.
- **Redaction** — `api_key=` stripped from logged URLs automatically.
- **Instrumentation** — emits `contractkit.request.start` /
  `.request.finish` / `.retry` / `.rate_limit_wait` / `.error` events
  via the configured `on_event` block AND through
  `ActiveSupport::Notifications` if AS is loaded.
- **Cache** — opt-in via `c.cache = ...`; GETs only; SHA256 key over
  method + canonical URL + body.

See [`docs/design/reliability.md`](docs/design/reliability.md) for the
full design rationale.

## Endpoint Map

### SAM.gov

| Endpoint | Used by | Notes |
|---|---|---|
| `GET /opportunities/v2/search` | `Opportunity.search`, `Opportunity.modified_since`, `Recompete.expiring` | Primary. Offset/limit pagination, max 1000/page |
| `GET /opportunities/v2/{noticeId}` | `Opportunity.find` | Single notice lookup |
| `GET /entity-information/v3/entities` | `Recipient.find_entity` | SAM Entity Management (registration, exclusions, ownership) |

### USASpending.gov

| Endpoint | Method | Used by | Notes |
|---|---|---|---|
| `/search/spending_by_award/` | POST | `Award.search`, `Idv.search`, `CrossReference.awards_for` | Primary. Page-based, max 100/page |
| `/awards/{id}/` | GET | `ResponseParser.parse_detail` | Rich single-award detail (pricing, competition) |
| `/recipient/{uei}/` | GET | `Recipient.find` | Recipient lookup |
| `/api/v2/transactions/` | POST | `Transaction.for_award` | Per-modification history |
| `/api/v2/subawards/` | POST | `Subaward.for_award` | Prime→sub teaming |

## Error hierarchy

```
Contractkit::Error                       # base; carries endpoint, http_method,
  ├── NotFoundError                      # params, status, response_snippet
  ├── AuthenticationError
  ├── ServerError
  ├── MalformedResponseError
  ├── ConfigurationError                 # raised before HTTP — bad config
  └── RateLimitError                     # exposes retry_after
       ├── Sam::RateLimitError           # per-API subclasses inherit from
       └── Usaspending::RateLimitError   # the cross-API parent
```

Rescue cross-API (`Contractkit::RateLimitError`) or narrowly
(`Contractkit::Sam::RateLimitError`) — both work.

## What `contractkit` does NOT do

Explicit non-goals; some deferred to v0.2, some permanent:

- **No persistence.** No ActiveRecord, no DB adapter. Consumers persist
  the objects however they want.
- **No scoring / ML / win probability.** That's consumer product IP.
  The gem ends at "here's the data and the join."
- **No user model.** No `User`, no `ContractorProfile`, no auth.
- **No scheduling.** Consumers wrap the gem's methods in their own
  cron / ActiveJob / etc.
- **No enrichment from non-SAM/non-USASpending sources** (no LinkedIn,
  no Crunchbase, no LLM scope extraction, no CPARS).
- **No UI**, no CLI binary beyond `bin/console`, no async I/O.

Deferred to **v0.2** (see [CHANGELOG.md](CHANGELOG.md) for the
roadmap):

- Full NAICS 2022 coverage (~1100 codes) — v0.1 ships ~40
- Full PSC coverage (~5000 codes) — v0.1 ships ~25
- Sub-tier agency normalization (DoD service branches, DHS components, etc.)
- `Award.find` via USASpending's `/awards/{id}/` endpoint
- Async / streaming clients

## Documentation

- [Domain](docs/domain/) — how the SAM and USASpending APIs actually
  work in production (rate limits, quirks, field dictionaries,
  cross-system joining)
- [Design](docs/design/) — data flow diagrams, data models, reliability,
  packaging, Vindor extraction plan
- [Contributing](docs/contributing/) — architecture overview and the
  documentation guide

For a YARD-built API reference: `bundle exec yard doc && open doc/index.html`.

## Example Scripts

| Script | What it demonstrates |
|---|---|
| [`examples/basic_usage.rb`](examples/basic_usage.rb) | End-to-end smoke test: Opportunity search, Award search, cross-reference, multi-tenant client, instrumentation |
| [`examples/find_recompetes.rb`](examples/find_recompetes.rb) | Recompete detection: search opportunities, cross-reference to awards, print incumbent summary table |
| [`examples/query_idvs.rb`](examples/query_idvs.rb) | IDV search, parent/child traversal, `last_date_to_order` recompete signal |
| [`examples/query_transactions.rb`](examples/query_transactions.rb) | Transaction history for an award with `action_type` analysis |
| [`examples/query_subawards.rb`](examples/query_subawards.rb) | Subaward teaming patterns for an award |
| [`examples/query_entities.rb`](examples/query_entities.rb) | SAM entity enrichment: registration status, exclusions, business types, ownership |

All examples need a `SAM_API_KEY` env var. Run with:
```bash
SAM_API_KEY=<your-key> bundle exec ruby examples/<script>.rb
```

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup, coding
conventions, the VCR cassette workflow, and pull request expectations.

Quick onboarding checklist:

- Read [`docs/contributing/architecture-overview.md`](docs/contributing/architecture-overview.md)
- Read [`docs/design/data-flow.md`](docs/design/data-flow.md)
- Run `bin/setup` then `bundle exec rake`

## License

MIT — see [LICENSE](LICENSE).
