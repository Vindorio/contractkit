# contractkit

> **Federal procurement data for Ruby.** Aggregates SAM.gov contract
> opportunities and USASpending.gov award history into a single,
> framework-agnostic gem with typed model objects, transparent
> pagination, opportunity-to-award cross-referencing, and built-in
> rate-limit / retry / redaction middleware.

[![Status](https://img.shields.io/badge/status-pre--alpha-orange)](#status)

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

See the [recompete script](examples/find_recompetes.rb) for an
end-to-end demo.

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
- Subaward / sub-recipient data
- Async / streaming clients

## Documentation

- [Domain](docs/domain/) — how the SAM and USASpending APIs actually
  work in production (rate limits, quirks, field dictionaries,
  cross-system joining)
- [Design](docs/design/) — data models, reliability, packaging,
  Vindor extraction plan
- [Contributing](docs/contributing/) — architecture overview and the
  documentation guide

For a YARD-built API reference: `bundle exec yard doc && open doc/index.html`.

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup, coding
conventions, the VCR cassette workflow, and pull request expectations.

Quick onboarding checklist:

- Read [`docs/contributing/architecture-overview.md`](docs/contributing/architecture-overview.md)
- Read [`docs/contributing/documentation-guide.md`](docs/contributing/documentation-guide.md)
- Run `bin/setup` then `bundle exec rake`

## License

MIT — see [LICENSE](LICENSE).
