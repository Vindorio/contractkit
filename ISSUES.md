# contractkit — GitHub Issues (v0.1.0)

> Pre-filing draft. Each issue below is sized for 1-3 focused sessions. Testing
> is folded into acceptance criteria rather than split into separate issues.
> Dependency graph at the end.
>
> Once the repo exists on GitHub, this file can be split into individual
> `gh issue create` calls (or pasted into the web UI). The titles, labels,
> and bodies are already in `gh`-compatible shape.
>
> Source material:
> - [[docs/domain/sam-gov]], [[docs/domain/usaspending]],
>   [[docs/domain/cross-referencing]], [[docs/domain/agency-normalization]],
>   [[docs/domain/naics-and-setasides]]
> - [[docs/design/data-models]], [[docs/design/reliability]],
>   [[docs/design/extraction-plan]], [[docs/design/packaging]]
> - [[docs/contributing/architecture-overview]], [[docs/contributing/documentation-guide]]

---

## Milestone M0 — Scaffolding

The repo is credible-looking from the first commit: gemspec, CI, basic README,
no real code yet.

### #1 Initialize gem skeleton (gemspec, version, layout)

**Labels:** `setup`, `packaging`

Create the `contractkit` gem skeleton matching the directory layout in
[[architecture-overview]]. Use `bundle gem contractkit --test=rspec --linter=rubocop --ci=github`
as the starting point, then prune to our preferences.

**Acceptance criteria:**
- `contractkit.gemspec` exists with name, summary (one sentence), homepage, license = `MIT`, Ruby 3.1+ floor, single runtime dep `faraday ~> 2.x`
- `lib/contractkit.rb` defines the module + version constant
- `lib/contractkit/version.rb` contains `VERSION = "0.0.1"`
- `Gemfile` references the gemspec
- `Rakefile` defines `default` -> `spec` and `lint`
- `bin/console` works with `irb` + the gem auto-required
- `bundle install` + `rake` both succeed on a fresh checkout
- No code in `lib/contractkit/` yet beyond the version

**Depends on:** none

---

### #2 Configure RuboCop with a minimal, opinionated ruleset

**Labels:** `setup`, `ci`

Adopt `rubocop`, `rubocop-rspec`, `rubocop-performance` with a small custom
overlay. We are not going to litigate style in code review.

**Acceptance criteria:**
- `.rubocop.yml` extends the three plugins above
- `Layout/LineLength` set to 100
- `Style/Documentation` disabled (YARD is the contract, not RDoc preamble)
- `Metrics/*` cops tuned for the parser files specifically (they're long by nature)
- `rake lint` runs cleanly on the empty scaffold

**Depends on:** #1

---

### #3 GitHub Actions CI — test + lint matrix

**Labels:** `ci`, `setup`

Matrixed CI per [[packaging]]. Must not require any external secrets.

**Acceptance criteria:**
- `.github/workflows/ci.yml` matrixes Ruby 3.1, 3.2, 3.3, 3.4
- Jobs: `test` (RSpec), `lint` (RuboCop), `audit` (`bundle audit --update`)
- Cache `~/.bundle` and `vendor/bundle` keyed on `Gemfile.lock` hash
- Workflow runs on `push` to default branch and on PRs
- All three jobs succeed on the empty scaffold

**Depends on:** #1, #2

---

### #4 RSpec setup + WebMock with no-real-HTTP guard

**Labels:** `testing`, `setup`

Test framework with a hard rule: no test ever talks to the real network.

**Acceptance criteria:**
- `spec/spec_helper.rb` requires `webmock/rspec`, sets `WebMock.disable_net_connect!`
- `spec/support/` directory autoloaded
- A meta-spec that asserts WebMock is active and any attempt to hit a real URL raises
- A placeholder unit spec passes
- VCR is **not** added in v0.1.0 (per [[packaging]] decision); WebMock + inline fixtures only

> ⚠️ FILL IN: Confirm the no-VCR call from [[packaging]] holds. If we want VCR for one or two scenarios, file a follow-up after #4 lands.

**Depends on:** #1

---

### #5 YARD setup with a coverage gate

**Labels:** `docs`, `ci`, `setup`

Per [[documentation-guide]], every public method gets YARD. CI enforces it.

**Acceptance criteria:**
- `.yardopts` exists with `--markup markdown`, `--protected`, `--no-private`
- `rake docs` builds local docs successfully
- A `docs-coverage` CI job runs `yard stats --list-undoc` and fails if any public method is undocumented (zero-tolerance — the codebase is small enough to hold the line on day one)
- Generated docs are not committed (gitignore `doc/`)

**Depends on:** #1, #3

---

### #6 README v0 — install, why-this-exists, minimal usage

**Labels:** `docs`, `setup`

Credible day-one README per the outline in [[packaging]]. Must read as
"this is a real project," not a placeholder.

**Acceptance criteria:**
- Sections: Why, Install, Quick Start, Configuration, Status (alpha banner), License, Contributing
- "Why" paragraph explains the two-API aggregation thesis in 4-6 sentences
- "Quick Start" includes one runnable code snippet (even if the methods are stubbed; the README example must mirror reality)
- "Status" banner clearly says pre-1.0, API may change
- No marketing language

**Depends on:** #1

---

### #7 MIT LICENSE + CHANGELOG seed + CONTRIBUTING.md

**Labels:** `docs`, `packaging`

**Acceptance criteria:**
- `LICENSE` is verbatim MIT, copyright current year + author name
- `CHANGELOG.md` follows Keep-a-Changelog format with an `[Unreleased]` header
- `CONTRIBUTING.md` links to the `docs/contributing/` directory and states the YARD-coverage requirement

**Depends on:** #1

---

## Milestone M1 — Core Clients

The HTTP layer, both API clients, pagination, configuration, errors. End of
M1, you can run a SAM search and a USASpending search and get raw hashes back.

### #8 Error hierarchy

**Labels:** `api-client`, `enhancement`

Lift the *shape* of Vindor's `Errors::*` per [[extraction-plan]] #11 — base
`Contractkit::Error`, then `NotFoundError`, `RateLimitError`,
`AuthenticationError`, `ServerError`, `MalformedResponseError`,
`ConfigurationError`. Per-API namespacing (`Contractkit::Error::Sam::RateLimit`)
inherits from the cross-API parent.

**Acceptance criteria:**
- All errors in `lib/contractkit/error.rb`
- Every error class carries `endpoint`, `http_method`, `params`, `status`, `response_snippet` as readers
- `RateLimitError` exposes `retry_after`
- Unit specs: each class instantiates, carries fields, walks the hierarchy correctly (`rescue Contractkit::Error` catches everything)

**Depends on:** #1

---

### #9 Configuration singleton + Client instance

**Labels:** `api-client`, `enhancement`

Per the [[architecture-overview]] config flow. Global config + instance
client with the same fields.

**Acceptance criteria:**
- `Contractkit::Configuration` holds `sam_api_key`, `user_agent`, `timeout`, `retries`, `logger`, `cache`, `cache_ttl`
- `Contractkit.configure { |c| ... }` yields the singleton
- `Contractkit::Client.new(...)` accepts the same options without touching globals
- Two independent `Client.new` instances do not share state
- `Configuration` access is monitor-synchronized for thread safety
- Specs cover override precedence (instance > block override > global default)

**Depends on:** #8

---

### #10 Faraday HTTP connection with retry + redaction middleware

**Labels:** `api-client`, `enhancement`

The shared transport per [[reliability]]. Retry policy (exponential backoff
on 5xx + network errors, NOT on 4xx), API-key redaction in log lines.

**Acceptance criteria:**
- `lib/contractkit/http/connection.rb` exposes a `build(config)` returning a Faraday connection
- Middleware stack (in order): rate limiter → retry → redactor → logger → adapter
- Retry middleware: configurable retries (default 3), exponential backoff with jitter (250ms / 500ms / 1s), retry conditions = `[500, 502, 503, 504, :timeout, :connection_failed]`, never retry 4xx
- Redactor strips `api_key` from request URL/params in log output
- Connect timeout default 5s, read timeout default 30s, both per-config-overridable
- Specs cover: 500 retried then succeeds; 401 not retried; api_key redacted from a captured log line

**Depends on:** #9

---

### #11 Token-bucket rate limiter middleware

**Labels:** `api-client`, `enhancement`

Per-API token bucket per [[reliability]]. SAM default 20 req/min sustained,
USASpending default 5 req/sec. Configurable; defaults are conservative.

**Acceptance criteria:**
- `lib/contractkit/http/rate_limiter.rb` implements a simple token-bucket
- Per-host bucket keyed on `request.uri.host`
- Bucket waits (blocking) when empty rather than raising; surfaces `RateLimitError` only when the upstream returns 429
- On 429 with `Retry-After`, drains the bucket so the next attempt respects the upstream window
- Specs cover: 30 rapid calls against a stub take roughly 1 minute under SAM defaults; 429 with `Retry-After: 5` causes a 5s drain

**Depends on:** #10

---

### #12 SAM.gov raw client + pagination

**Labels:** `api-client`, `enhancement`

Rewrite (not extract) per [[extraction-plan]] #1. Copy verbatim from Vindor:
date format `%m/%d/%Y`, `PTYPES = %w[p o]`, the field set in
`FetchOpportunitiesJob`.

**Acceptance criteria:**
- `Contractkit::Sam::Client#raw_search(params)` returns the parsed JSON hash from `/opportunities/v2/search`
- `Contractkit::Sam::Pagination::Offset` wraps `raw_search` in a lazy Enumerable per [[architecture-overview]]
- Pagination handles SAM's `totalRecords` + `offset` + `limit` semantics; stops on empty `opportunitiesData`
- Date params accept `Date` and convert to SAM's `%m/%d/%Y` format
- Specs cover (against WebMock fixtures): single-page response, multi-page response, empty response, 401 missing key, 429 with `Retry-After`

**Depends on:** #10, #11

---

### #13 USASpending.gov raw client + pagination

**Labels:** `api-client`, `enhancement`

Rewrite per [[extraction-plan]] #2. Copy verbatim from Vindor:
the `FIELDS` list (20 fields, `FetchAwardsJob` L17-38), the
`CONTRACT_AWARD_TYPE_CODES = %w[A B C D]` filter, page-based pagination.

**Acceptance criteria:**
- `Contractkit::Usaspending::Client#raw_search(filters:, fields:, page:, limit:)` POSTs to `/api/v2/search/spending_by_award/`
- `Contractkit::Usaspending::Client#raw_recipient(uei)` GETs `/api/v2/recipient/duns/{uei}/`
- `Contractkit::Usaspending::Pagination::Page` lazy Enumerable; stops on `page_metadata.hasNext == false`
- Default `fields` list shipped as a frozen constant; callers can override per request
- Specs cover: paginated response across 3 pages; empty response; timeout on a wide query (per [[usaspending]] known quirk)

**Depends on:** #10, #11

---

### #14 Instrumentation hooks (block-based + AS::Notifications optional)

**Labels:** `api-client`, `enhancement`

Per [[reliability]] §logging. Framework-agnostic — works without Rails;
auto-uses `ActiveSupport::Notifications` if loaded.

**Acceptance criteria:**
- `Contractkit.configure { |c| c.on_event { |name, payload| ... } }` registers a block
- Events emitted: `contractkit.request.start`, `contractkit.request.finish`, `contractkit.retry`, `contractkit.rate_limit_wait`, `contractkit.error`
- If `ActiveSupport::Notifications` is loaded, the same events emit through it as well (auto-detected)
- Specs cover both the block-hook path and (with ActiveSupport in dev dependencies) the AS::Notifications path

**Depends on:** #10

---

### #15 Pluggable response cache middleware (opt-in)

**Labels:** `api-client`, `enhancement`

Per [[reliability]] §caching. Off by default. Plugs into anything responding
to `#read(key)` / `#write(key, value, ttl:)`.

**Acceptance criteria:**
- `Contractkit::Http::CacheMiddleware` honors `config.cache` and `config.cache_ttl`
- Only `GET` requests are cached
- Cache key = SHA256 of `verb + url + sorted_query_string + body_hash`
- If `config.cache` is nil, middleware is a no-op
- Specs cover: cache hit returns identical response without HTTP call; cache miss writes; nil cache short-circuits cleanly

**Depends on:** #10

---

## Milestone M2 — Data Models

Normalized models, parsers, value objects, cross-referencing. End of M2,
the public API in [[docs/design/data-models]] is fully callable.

### #16 `Opportunity` model + SAM response parser

**Labels:** `data-model`, `enhancement`

Extract `BuildContractsJob#extract` per [[extraction-plan]] #3 (after
removing the Rails couplings called out in the doc).

**Acceptance criteria:**
- `Contractkit::Opportunity` plain Ruby class with all readers per [[data-models]]
- `.raw` returns the original SAM JSON; `.to_h` returns the normalized hash
- `Contractkit::Sam::ResponseParser` translates a single notice hash → `Opportunity` instance
- Handles the `placeOfPerformance.state` two-shape polymorphism per [[sam-gov]] known issue
- Handles integer-vs-string `naicsCode` (zero-pads to 6 chars)
- Specs cover: full notice; sparse notice; both state shapes; integer NAICS; missing optional fields

**Depends on:** #12

---

### #17 `Opportunity.search` and `.find` and `.modified_since`

**Labels:** `data-model`, `enhancement`

Wire the resource module surface over the raw client + parser.

**Acceptance criteria:**
- `Contractkit::Opportunity.search(...)` accepts the params in [[data-models]] / the API design sketch; returns a lazy Enumerable of `Opportunity` instances
- `.find(notice_id)` returns a single `Opportunity` or raises `NotFoundError`
- `.modified_since(time)` yields each `Opportunity` to a block AND returns a lazy Enumerable when no block given
- Multiple NAICS values trigger sequential requests (per [[sam-gov]] one-NAICS-per-query constraint), surfaced as one merged lazy Enumerable
- Specs cover the merging behavior plus the single-NAICS happy path

**Depends on:** #16

---

### #18 `Award` model + USASpending response parser

**Labels:** `data-model`, `enhancement`

Plain Ruby model per [[data-models]]. Handles the obligated-vs-ceiling
money-field confusion (`obligated_amount` is the headline).

**Acceptance criteria:**
- `Contractkit::Award` with readers per [[data-models]]; `.raw` and `.to_h` present
- `Award#obligated_amount` returns `BigDecimal`; ceiling exposed separately as `Award#ceiling`
- `Award#period` returns a value object with `start_date` and `end_date` as `Date` (not DateTime)
- `Contractkit::Usaspending::ResponseParser` translates one award hash → `Award`
- Specs cover: full award; missing optional fields; the obligated/ceiling distinction

**Depends on:** #13

---

### #19 `Award.search`, `.find`, `.updated_since`, `Recipient` lookup

**Labels:** `data-model`, `enhancement`

Resource modules wired over raw client + parser.

**Acceptance criteria:**
- `Contractkit::Award.search(...)` accepts the documented filters; returns a lazy Enumerable of `Award`
- `.find(award_id)` (the `generated_unique_award_id`) returns one award
- `.updated_since(time)` mirrors the SAM equivalent
- `Contractkit::Recipient.find(uei)` returns a `Recipient` value object (per [[data-models]])
- Specs cover happy paths against fixtures + sparse-field cases

**Depends on:** #18

---

### #20 `Agency` value object + baseline alias table (v0.1 minimal)

**Labels:** `data-model`, `enhancement`

Per [[extraction-plan]] #4, the full curated alias table is L-effort and
deferred to v0.2. v0.1 ships the **value object** + a **minimal seed of the
top ~25 cabinet departments** as the baseline, plus the `register_alias`
override hook.

**Acceptance criteria:**
- `Contractkit::Agency` value object: `canonical`, `toptier_code`, `subtier_code`, `subtier_name`, `full_path`
- `Contractkit::Agency.normalize(input)` returns an `Agency` instance using: (1) code match → (2) baseline aliases → (3) Vindor-style `full.split(".").first` heuristic fallback
- `Contractkit::Agency.register_alias(name, canonical:, toptier_code:)` mutates an in-process table
- `lib/contractkit/data/agency_aliases.json` ships with cabinet-level + DoD service branches + VA + DHS top variants (~50 entries)
- Specs cover all three normalization paths and the override hook
- Doc note in [[agency-normalization]] flagged that full coverage is v0.2

**Depends on:** #16, #18

---

### #21 `Naics` value object + lookup table (NAICS 2022)

**Labels:** `data-model`, `enhancement`

Ship NAICS 2022 as static data per [[naics-and-setasides]].

**Acceptance criteria:**
- `lib/contractkit/data/naics_2022.json` contains all ~1100 6-digit entries with code, title, sector_code, sector_title, subsector_code, subsector_title
- `Contractkit::Naics.lookup("541512")` returns a `Naics` value object
- `Naics#sector`, `#subsector` return the parent values (also `Naics` objects)
- Data is loaded eagerly at require-time and frozen (memory cost is trivial)
- Specs cover: known code lookup; unknown code returns `nil`; sector/subsector chains

**Depends on:** #1 (no other code deps; can be parallelized)

> ⚠️ FILL IN: Source pinning — link to the exact Census Bureau NAICS 2022 CSV used to generate the JSON, with a script under `script/regenerate_naics.rb`.

---

### #22 `SetAside` normalizer + label table

**Labels:** `data-model`, `enhancement`

Per [[naics-and-setasides]] + [[extraction-plan]] #6. Carry forward only
the *field locations* from Vindor; build the codes-to-labels table fresh.

**Acceptance criteria:**
- `lib/contractkit/data/set_aside_codes.json` contains every SAM-documented code → symbol mapping
- `Contractkit::SetAside.normalize(raw)` accepts SAM codes, USASpending codes, human strings; returns a Ruby symbol
- `Contractkit::SetAside.label(symbol)` returns the canonical human string
- Specs cover: every documented code; empty/nil → `:none`; unknown code → raises `Contractkit::Error` with a clear message (not `ArgumentError`)

**Depends on:** #1 (parallelizable with #21)

---

### #23 `Psc` value object + lookup table

**Labels:** `data-model`, `enhancement`

Per [[naics-and-setasides]]. Smaller scope than NAICS but ships in v0.1
because cross-referencing uses it as a tightener.

**Acceptance criteria:**
- `lib/contractkit/data/psc.json` contains 4-char PSC codes + titles + first-character category
- `Contractkit::Psc.lookup(code)` returns a `Psc` value object with `category` accessor (the prefix-letter family)
- Specs cover: known codes from each major prefix; unknown → `nil`

**Depends on:** #1 (parallelizable)

---

### #24 `CrossReference` + `Opportunity#related_awards` + `#likely_incumbent`

**Labels:** `data-model`, `enhancement`

Per [[extraction-plan]] #8 and [[cross-referencing]]. The join key is
preserved verbatim from Vindor (`agency_top + naics6 + place_of_perf_state`);
the mechanism is rewritten as an HTTP call to USASpending.

**Acceptance criteria:**
- `Contractkit::CrossReference.awards_for(opportunity:, lookback:, ending_window:, match:, limit:)` returns an array of `Award`
- Default `match: [:agency, :naics]`; `:psc` is opt-in
- `Opportunity#related_awards(**opts)` delegates to `CrossReference`
- `Opportunity#likely_incumbent` returns a `Recipient` if one recipient holds >50% of obligation, otherwise `nil` (per [[cross-referencing]] decision; never force a guess)
- Specs cover: clear incumbent (one dominant recipient); ambiguous (multi-award IDIQ) → nil; empty result; PSC tightener narrows results

**Depends on:** #17, #19, #20

---

### #25 `PlaceOfPerformance` value object + two-shape `state` normalizer

**Labels:** `data-model`, `enhancement`

Per the placeOfPerformance polymorphism issue in [[sam-gov]]. Small but
load-bearing.

**Acceptance criteria:**
- `Contractkit::PlaceOfPerformance` with `state` (2-letter code), `city`, `country`, `zip` readers
- Parser handles both `state: "VA"` and `state: { code: "VA", name: "Virginia" }` shapes
- Specs cover both shapes plus missing fields

**Depends on:** #16

---

## Milestone M3 — Ship It

Polish, examples, release infrastructure, the dogfood.

### #26 Examples directory — recompete-detection canonical script

**Labels:** `docs`, `enhancement`

One executable script that demonstrates the gem's flagship use case.

**Acceptance criteria:**
- `examples/find_recompetes.rb` is a standalone script (run with `bundle exec ruby examples/find_recompetes.rb`)
- Script: configures the gem from `ENV`, searches recent NAICS 541512 opportunities, calls `related_awards` on each, prints a summary table with `Opportunity#likely_incumbent`
- Script runs end-to-end against live APIs given a SAM key (manually verified; not part of CI)
- README "Quick Start" section references this example

**Depends on:** #24

---

### #27 README polish — full usage examples, contributing pointer

**Labels:** `docs`

Replace the v0 README with full content.

**Acceptance criteria:**
- All sections in [[packaging]] §README outline are filled in
- "Configuration" section covers every config field
- "Cross-referencing" section uses the example from #26
- "Status" banner updated for "0.1.0 release candidate"
- "Contributing" links to `CONTRIBUTING.md` and `docs/contributing/`
- Mention the absence of v0.1 features (full agency normalization, async fetch, subawards) and link to follow-up issues

**Depends on:** #26

---

### #28 RubyGems trusted publishing setup

**Labels:** `packaging`, `ci`

Per [[packaging]] §release-process. No long-lived API keys.

**Acceptance criteria:**
- `.github/workflows/release.yml` triggers on tag push matching `v*.*.*`
- Workflow uses `rubygems/release-gem@v1` (or current trusted-publishing action) with OIDC
- Trusted-publishing config registered on rubygems.org for this gem (manual step; document in CONTRIBUTING)
- Workflow runs the full CI suite before publishing, and aborts on any failure

> ⚠️ FILL IN: Confirm the exact action name once we know the current best-practice — `rubygems/release-gem` vs `rubygems/configure-rubygems-credentials`.

**Depends on:** #3

---

### #29 0.1.0 release tag + CHANGELOG entry

**Labels:** `packaging`

The release itself, treated as a discrete unit of work.

**Acceptance criteria:**
- `CHANGELOG.md` `[Unreleased]` content moved under a new `[0.1.0]` header with today's date
- `lib/contractkit/version.rb` bumped to `"0.1.0"`
- Git tag `v0.1.0` pushed
- Release workflow (#28) publishes successfully to rubygems.org
- `gem install contractkit` works from a clean machine

**Depends on:** #27, #28, plus every M2 issue

---

### #30 Dogfood — migrate Vindor to consume `contractkit`

**Labels:** `enhancement`

Vindor becomes the first real consumer of the gem. This issue lives in
the Vindor repo, not the contractkit repo — referenced here for tracking
because it's the acceptance test for v0.1.0.

**Acceptance criteria (in Vindor):**
- Vindor's `FetchOpportunitiesJob` and `FetchAwardsJob` are rewritten to call `Contractkit::Opportunity.search` / `Contractkit::Award.search` instead of `Net::HTTP`
- Vindor's `BuildContractsJob#extract` is deleted; persistence reads from `Contractkit::Opportunity#to_h`
- Vindor's `EnrichContractsJob` Postgres JSONB join is replaced by `Opportunity#related_awards`
- All existing Vindor tests pass
- Vindor's contract-fetch pipeline produces equivalent rows (sample diff captured) before/after
- Any contractkit gaps discovered during dogfood are filed back as new issues against contractkit

**Depends on:** #29

---

## Dependency graph

```
M0 (parallel-ish):
  #1 init  ─┬─► #2 rubocop ─► #3 CI ─┐
            ├─► #4 RSpec/WebMock ────┤
            ├─► #5 YARD ─────────────┤
            ├─► #6 README v0         │
            └─► #7 LICENSE/CHG/CONTR │
                                     │
M1 (mostly serial on the HTTP stack):│
  #8 errors ─► #9 config/client ─► #10 connection ─┬─► #11 rate limiter ─┬─► #12 SAM client
                                                    │                     ├─► #13 USAsp client
                                                    ├─► #14 instrumentation
                                                    └─► #15 cache middleware

M2 (parallel branches under M1):
  #12 ─► #16 Opportunity ─► #17 Opp.search/find/modified_since
                       └──► #25 PlaceOfPerformance
  #13 ─► #18 Award ──► #19 Award.search/find/updated_since + Recipient
  #1  ─► #21 Naics  (parallel)
  #1  ─► #22 SetAside (parallel)
  #1  ─► #23 Psc (parallel)
  #16+#18 ─► #20 Agency
  #17+#19+#20 ─► #24 CrossReference

M3:
  #24 ─► #26 examples ─► #27 README polish ─┐
  #3  ─► #28 release workflow ──────────────┤
                                            ├─► #29 0.1.0 release ─► #30 Vindor dogfood
  all M2 ─────────────────────────────────────┘
```

## Critical path

`#1 → #8 → #9 → #10 → #11 → #12 → #16 → #17 → #24 → #26 → #27 → #29`

That's the 12 issues that must be done in order. Everything else parallelizes
around them. With one full-time contributor: ~3-4 weeks to #29.
With two contributors splitting at the M2 branch point: ~2-3 weeks.

> ⚠️ FILL IN: Confirm we want #20 (Agency) in v0.1 with only the cabinet-level seed table, or whether we'd rather defer it entirely and let consumers normalize agencies themselves. The extraction plan flags the full table as L-effort and v0.2.
