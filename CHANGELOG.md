# Changelog

All notable changes to this project are documented here. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Release badges** in README: GitHub release version + changelog link.
  First GitHub Release (v0.1.0) published at
  https://github.com/gudetimes1234/contractkit/releases — future releases
  are auto-created by the release workflow on tag push.
- **Updates page** on Vindor (`/updates`) — users can see release notes
  and changelog for the gem that powers their contract matches.
- **Rake task** `updates:sync` in the Vindor repo that fetches latest
  GitHub releases for contractkit and writes them to
  `lib/data/contractkit_releases.yml` for the Updates page.

### Added — M4: Recompete & Pricing Intelligence

- **Award expansion** (#36): `Contractkit::Award` gains the full
  three-tier pricing surface (`obligated_amount` ≤
  `base_and_exercised_options_value` ≤ `base_and_all_options_value` /
  `total_contract_value`) plus competition fields
  (`number_of_offers_received`, `extent_competed`,
  `type_of_contract_pricing`, `contract_award_type`,
  `solicitation_procedures`). Competition fields populate only via the
  new `ResponseParser.parse_detail` path; bulk search rows leave them
  nil. See `docs/domain/award-pricing.md`.
- **IDV model** (#37): new `Contractkit::Idv` for indefinite-delivery
  vehicles (IDC / GWAC / BPA / BOA / FSS). Carries `last_date_to_order`
  — the primary recompete signal. `Contractkit::Idv.search` auto-injects
  `IDV_AWARD_TYPE_CODES` into the USASpending filter. `Award#parent_idv`
  and `Idv#child_awards` traverse the parent/child relationship.
  See `docs/domain/idvs.md`.
- **Transaction model** (#38): new `Contractkit::Transaction` for
  per-modification history from `/api/v2/transactions/`.
  `Award#transactions` and `Idv#transactions` lazy-fetch the stream.
  Surfaces raw `action_type` (CodedValue) — no option-exercise inference.
  See `docs/domain/transactions.md`.
- **Recipient enrichment** (#39): `Contractkit::Recipient` gains SAM
  Entity Management fields (registration_status, sam_expiration_date,
  cage_code, business_types, sba_business_types, naics_list,
  exclusion_status_flag, immediate_owner, highest_owner, …) plus
  `#excluded?` / `#registration_expired?` predicates. New
  `Contractkit::Sam::Entities` client + parser + `Recipient.find_entity`.
  USASpending-built recipients stay un-enriched; enrichment is opt-in.
  See `docs/domain/entities.md`.
- **Subaward model** (#40): new `Contractkit::Subaward` for one-level
  prime → sub teaming from `/api/v2/search/spending_by_subaward/`.
  `Award#subawards` lazy-fetches. FFATA threshold + reporting-compliance
  caveats documented; multi-tier explicitly out of scope.
  See `docs/domain/subawards.md`.
- **Recompete helper** (#41): new `Contractkit::Recompete.expiring(within:)`
  — time-forward sibling of `CrossReference.awards_for`. Pairs each
  expiring IDV / contract with matching active SAM solicitations using
  the same `match:` vocabulary. Block + Enumerator forms; streams
  without accumulating. `within:` accepts plain Integer (months) or any
  object responding to `#in_months` (so ActiveSupport::Duration works
  without a hard dependency). See `docs/domain/recompete.md`.
- New value object `Contractkit::CodedValue` for `(code, description)`
  pairs across the M4 fields (extent_competed, type_of_contract_pricing,
  action_type, business_types, …).
- New value object `Contractkit::OwnerReference` for SAM corporate
  hierarchy.

### Changed

- `Contractkit::CrossReference::DEFAULT_ENDING_WINDOW_MONTHS` is now
  `12` (was 24, reserved). The comment is updated to point at
  `Contractkit::Recompete` for the time-forward helper that consumes it.
- **Subaward bulk search removed upstream** — USASpending deleted
  `/api/v2/search/spending_by_subaward/` (verified 404, 2026-05-24).
  `Contractkit::Usaspending::Client#subawards` now takes `award_id:`
  and posts to `/api/v2/subawards/`. `Contractkit::Subaward.search`
  raises `NotImplementedError` directing callers to `.for_award`.
- **Parser field names verified live** (2026-05-24): `parse_idv` now
  reads the IDV type code from top-level `hash["type"]` (no
  `idv_type` key exists upstream); `parse_detail` documents that
  pricing fields land at top-level `base_and_all_options` /
  `base_exercised_options` / `total_obligation` and that there is no
  separate `total_contract_value` key (falls back to
  `base_and_all_options`). FIXME(M4) markers cleared except for the
  SAM Entities client, which remains unverified (SAM key was
  rate-limited at sign-off).

### Deferred — follow-up issues to file from PR

- Dedicated `Contractkit::Sam::Exclusions` client for historical /
  multi-record exclusion lookup. M4 ships exclusion *status* via the
  Entities response; the historical surface is filed separately.
- Live VCR cassettes for the SAM Entities endpoint. The USASpending
  detail / IDV / transactions / subawards endpoints are now covered
  by parser-shape specs against committed live response fixtures in
  `spec/fixtures/live_responses/`; SAM remains synthetic-only because
  the API key was throttled at sign-off.

## [0.1.0] - 2026-05-24

Initial release. Pre-alpha. API surface and shipped data tables may
expand in 0.x releases without ceremony; we'll be conservative once we
hit 1.0.

### Added

**Foundation**
- Gem skeleton (gemspec, lib/, Gemfile, Rakefile, bin/console, bin/setup)
- Ruby 3.2+ floor; single runtime dep `faraday ~> 2.0` (+ `faraday-retry ~> 2.0`)
- RuboCop config (line length 100, frozen string literals, parser-files
  metric carve-outs)
- GitHub Actions CI matrixed across Ruby 3.2-3.4 (test + lint + audit)
- RSpec test framework with VCR (cassette-based replay) + WebMock
  (no-real-HTTP guard); custom `:uri_ignoring_api_key` matcher so
  cassettes replay regardless of whether `SAM_API_KEY` is set in CI
- YARD documentation with 100% public-API coverage
- RubyGems trusted-publishing release workflow (OIDC; no long-lived
  API key in CI secrets)

**HTTP transport (`Contractkit::Http`)**
- Faraday connection builder wiring the gem's middleware stack in the
  right order: cache → rate limiter → retry → instrumentation → logger
  → adapter
- Per-host token-bucket rate limiter; SAM default 20 req/min,
  USASpending default 5 req/sec; honors `Retry-After` on 429
- Exponential-backoff retry with jitter (5xx and network errors only;
  4xx never retried — 429 belongs to the rate limiter)
- API-key redaction in log lines
- Opt-in response cache middleware (any `#read` / `#write` object;
  GETs only; SHA256-keyed on method + canonical URL + body hash)
- Instrumentation middleware emitting `contractkit.request.start /
  finish / retry / rate_limit_wait / error` events via a configurable
  block hook AND through `ActiveSupport::Notifications` when AS is
  loaded (never a runtime dep)

**Configuration**
- `Contractkit.configure { |c| ... }` global singleton (Stripe-style)
- `Contractkit::Client.new(...)` instance-scoped (Octokit-style) for
  multi-tenant consumers; configs do not share state
- Options: `sam_api_key` (env-aware), `user_agent`, `timeout`,
  `retries`, `logger`, `cache`, `cache_ttl`, `agency_aliases`,
  `on_event`
- Monitor-synchronized for thread safety; unknown option keys raise
  `Contractkit::ConfigurationError` at construction (typo guard)

**Error hierarchy**
- Cross-API base `Contractkit::Error` carrying `endpoint`,
  `http_method`, `params`, `status`, `response_snippet`
- Subclasses: `NotFoundError`, `AuthenticationError`, `ServerError`,
  `MalformedResponseError`, `ConfigurationError`, `RateLimitError`
  (with `retry_after`)
- Per-API namespacing under `Contractkit::Sam::*` and
  `Contractkit::Usaspending::*` inheriting from the cross-API parents
  (rescue narrowly or broadly — both work)

**SAM.gov client (`Contractkit::Sam::Client`)**
- `#raw_search(**params)` → parsed JSON hash from `/opportunities/v2/search`
- `#search(**params, &block)` → batch yield (one batch per upstream
  page; default 1000-per-page); lazy Enumerator without block; optional
  `limit:` caps total records
- Date params (`postedFrom`, `postedTo`) accept Ruby `Date`,
  auto-converted to SAM's `%m/%d/%Y`
- Default `ptype` filter = presolicitation + solicitation; default
  `ncode` filter empty (caller must supply for useful results)
- Empirical 404-on-bad-key behavior surfaced as
  `Sam::AuthenticationError` (SAM returns 404 with empty body for
  rejected keys on this endpoint, not the documented api.data.gov 403
  shape — see `lib/contractkit/sam/client.rb` for the rationale)

**USASpending.gov client (`Contractkit::Usaspending::Client`)**
- `#raw_search(filters:, fields:, page:, limit:)` → POST to
  `/api/v2/search/spending_by_award/`
- `#raw_recipient(uei)` → GET `/api/v2/recipient/duns/{uei}/`
  (the "duns" path is legacy; USASpending kept it stable after the
  2022 UEI migration)
- `#search(filters:, fields:, limit:, per_page:, &block)` → batch
  yield (one batch per upstream page; default 100-per-page);
  Enumerator without block
- Default `award_type_codes` filter = A/B/C/D (contracts)
- Default `fields` list ships as a frozen constant (20 fields covering
  the most useful subset; consumers override per request)

**Typed data models**
- `Contractkit::Opportunity` (frozen value object; 22 readers covering
  the SAM notice field set)
  - Class methods: `.search`, `.find`, `.modified_since`
  - Instance methods: `#related_awards`, `#likely_incumbent`,
    `#to_h`, `#raw`
- `Contractkit::Award` (frozen value object; 18 readers; `BigDecimal`
  money fields with `#obligated_amount` and `#ceiling` exposed
  separately)
  - Class methods: `.search`, `.updated_since`
  - `.find` raises `NotImplementedError` pointing at v0.2 (the
    `/awards/{id}/` endpoint has a different JSON shape needing its
    own parser path)
- `Contractkit::OpportunitySearch` / `Contractkit::AwardSearch` — lazy
  result handles; `#each` (record-level, yields typed objects);
  `#each_batch` (yields `Array<Typed>` per upstream page)
- `Contractkit::Recipient` (frozen; name, uei, duns, recipient_id +
  `.find(uei)` class method)
- `Contractkit::Period` (frozen; start_date and end_date as `Date`)
- `Contractkit::PlaceOfPerformance` (frozen; handles SAM's two-shape
  `state` polymorphism — string or `{code, name}`)

**Normalized lookup tables**
- `Contractkit::Agency.normalize(input)` — 3-layer resolution:
  consumer-registered aliases (via `config.agency_aliases`) →
  shipped baseline → raw-string fallback (never raises, never nil)
- v0.1 baseline: ~25 cabinet-level entries (15 statutory cabinet
  departments + 10 major independents: GSA, NASA, EPA, SBA, USAID,
  NSF, SSA, OPM, NRC, USPS)
- `Contractkit::Naics.lookup(code)` — ~40 procurement-focused NAICS
  2022 entries with sector / subsector chains
- `Contractkit::Psc.lookup(code)` — ~25 PSC entries plus the full
  24-letter prefix-category map (`.category_for` works on unshipped
  codes too)
- `Contractkit::SetAside.normalize(input)` / `.label(symbol)` /
  `.code(symbol)` — SAM raw codes as source of truth, normalized to
  Ruby symbols, with human labels for UI. Unknown input raises
  `Contractkit::SetAside::UnknownCode`. `.safe_normalize` returns
  `:unknown` instead — used by parsers so one weird code doesn't blow
  up the surrounding record.

**Cross-reference**
- `Contractkit::CrossReference.awards_for(opportunity:, ...)` — joins
  SAM opportunities to USASpending awards via agency + NAICS (default)
  with `:psc` and `:state` opt-in tighteners and a configurable
  `lookback:` window (default 5 years)
- `Contractkit::CrossReference.likely_incumbent(awards)` — dominant
  >50% obligation heuristic; returns nil when ambiguous (multi-award
  IDIQ — never forces a guess)
- `Opportunity#related_awards` / `#likely_incumbent` — instance
  delegates

**Documentation**
- README with installation, quick-start, full-feature usage examples,
  configuration reference, error hierarchy, "what we don't do",
  v0.2 deferral list, contributing pointer
- CONTRIBUTING.md (setup, conventions, VCR workflow, PR expectations)
- `docs/domain/` — SAM, USASpending, agency normalization,
  set-asides+NAICS, cross-referencing
- `docs/design/` — data models, reliability, packaging, Vindor
  extraction plan
- `docs/contributing/` — architecture overview, doc style guide
- `examples/basic_usage.rb` — end-to-end smoke test demonstrating
  every public surface
- `examples/find_recompetes.rb` — recompete-detection canonical script

### Deferred to v0.2 (not in this release)

- `Award.find` via USASpending's `/api/v2/awards/{id}/` endpoint
  (needs a separate parser path — the GET-single-award response shape
  differs from spending_by_award's)
- Full NAICS 2022 coverage (~1100 codes — v0.1 ships ~40 of the
  highest-volume procurement codes)
- Full PSC coverage (~5000 codes — v0.1 ships ~25)
- Sub-tier agency normalization (DoD service branches, DHS components,
  HHS components, etc. — v0.1 is cabinet-level only)
- Long-tail independent agency coverage
- Subaward / sub-recipient data (USASpending exposes; data quality is
  poor)
- Async / streaming clients
- Recompete `ending_window` parameter on `CrossReference.awards_for`
  (USASpending doesn't expose a period-end filter on
  spending_by_award; reserved for v0.2 once we work out the right
  query shape)

### Known limitations

- SAM.gov rate limit on a per-key basis is tighter than documented
  (~20 req/min sustained vs the documented 60). The gem's default
  pacing is conservative to match.
- Cassettes can drift from upstream silently; re-record quarterly or
  when a spec yellows. See CONTRIBUTING.md §Recording cassettes.
- v0.1 ships only the search-endpoint code path; nothing else from
  SAM or USASpending is supported.

### Versioning policy

We follow [SemVer](https://semver.org/). For this gem specifically:

- **MAJOR** — public method removal, parameter rename on a public
  method, public model field rename, error-class rename
- **MINOR** — new public method, new model field (additive), new
  shipped data entry, new error subclass
- **PATCH** — bug fix, perf improvement, doc-only change, upstream
  API drift absorbed without surface change
- **Dropping a Ruby version** — MINOR with one release of overlap
  warning; never a PATCH

Pre-1.0 (0.x.y): MINOR may make breaking changes; PATCH won't. This
will become strict SemVer at 1.0.

---

[Unreleased]: https://github.com/gudetimes1234/contractkit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/gudetimes1234/contractkit/releases/tag/v0.1.0
