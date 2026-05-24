# contractkit — PRD

> Product requirements doc for the `contractkit` Ruby gem. Public-facing
> (lives in the gem repo and will be visible when the repo is opened).
>
> Companion docs:
> [[domain/sam-gov]], [[domain/usaspending]], [[design/data-models]],
> [[design/extraction-plan]], [[design/packaging]], [[ISSUES]].

---

## 1. Problem

Federal procurement data lives in two unrelated systems that nobody has
unified at the library layer.

**SAM.gov** publishes active contract opportunities (presolicitations,
solicitations, award notices). **USASpending.gov** publishes the
historical record of money actually obligated (every contract, grant,
loan, direct payment). Together they tell the whole story of a federal
procurement — what's coming, what's been done, who's incumbent. Apart,
they tell half of it.

The two systems are built by different agencies, expose different
schemas, use different naming conventions, encode the same entities
(agencies, NAICS, set-asides, recipients) in inconsistent ways, document
their rate limits inaccurately, and provide no shared identifier for the
same contract action across both. SAM requires an API key with
under-documented throttling behavior; USASpending tolerates more
concurrency but times out on wide queries. Both ship real-world
quirks (place-of-performance state returned as object-or-string,
solicitation numbers in inconsistent formats, agency-name drift) that
take months to discover and reproduce.

**Existing options for a Ruby developer:**

- Use `Net::HTTP` directly and re-discover every quirk yourself. (What
  Vindor did. Took months. Still has gaps.)
- Use a single-source thin client like `pysam` (Python, 14 stars,
  SAM-only). Doesn't unify with USASpending. Wrong language.
- Use a commercial scraper (Apify actors, various paid APIs). Expensive,
  rate-limited, no SLA, redistribution-restricted.
- Use the government's own `usaspending-api` Django backend as a
  reference. Massive surface area, designed as a hosted service not a
  library.

Nobody has built a **lightweight, framework-agnostic Ruby library that
unifies both sources** and surfaces a clean Ruby object model with the
cross-references that make the data actually useful (incumbent
detection, recompete identification, market sizing). That gap is the
reason for this gem.

## 2. Users

Three concrete user types in priority order:

**1. GovCon SaaS builders.** Companies building scoring, CRM,
capture-management, or BD tooling on top of federal procurement data.
They want to spend their engineering budget on their product
differentiator (scoring algorithms, UX, workflow), not on SAM.gov's
pagination edge cases. **This is the dogfood user — Vindor is consumer
#1.**

**2. Ruby-fluent BD / capture analysts at contractors.** Mid-size primes
and subs with a Rails-shop tools team. They write one-off scripts:
"show me every recompete in NAICS 541512 expiring in the next 18 months
at agencies where we have past performance." Today they pipe `curl` into
`jq`; tomorrow they call `Contractkit::Opportunity.search(...)`.

**3. Civic-tech / journalism researchers.** Public-interest analysis:
who got how much, from which agency, in which district. Awards-heavy
use case. Stress-tests the bulk-fetch and pagination paths.

**Explicitly not a target user:** the Python data-science crowd. They
have `pandas-datareader`-shaped expectations and won't switch languages
for one library. Don't design the API to court them.

## 3. What it does

Mapped to the milestone structure ([[ISSUES]] has the 30 filed issues).

### M0 — Scaffolding
- Standard gem packaging: `gemspec`, `Gemfile`, `Rakefile`, MIT license
- GitHub Actions CI matrixed across Ruby 3.1-3.4
- RSpec + WebMock with hermetic no-real-HTTP testing
- YARD with a coverage gate
- README, CHANGELOG, CONTRIBUTING

### M1 — Core clients
- **SAM.gov HTTP client.** `/opportunities/v2/search` with API-key auth,
  user-agent string, configurable timeouts, offset/limit pagination
  exposed as a lazy `Enumerable`.
- **USASpending.gov HTTP client.** `/api/v2/search/spending_by_award/`
  with POST-body filter construction, page-based pagination, recipient
  lookup.
- **Token-bucket rate limiter.** Per-host. Conservative defaults
  (SAM 20/min, USASpending 5/sec); configurable.
- **Retry middleware.** Exponential backoff on 5xx and network errors;
  never on 4xx. Honors `Retry-After` on 429.
- **Shallow error hierarchy.** `Contractkit::Error` base; concrete
  classes for `NotFound`, `RateLimit`, `Authentication`, `Server`,
  `MalformedResponse`, `Configuration`. Per-API namespacing for callers
  who want to rescue narrowly.
- **Global config + instance client.** `Contractkit.configure { ... }`
  for the 80% case; `Contractkit::Client.new(...)` for multi-tenancy.
- **Instrumentation hooks.** Block-based; auto-uses
  `ActiveSupport::Notifications` if loaded. Never requires it.
- **Pluggable response cache.** Opt-in. Any object with `#read` /
  `#write` works (Rails.cache, file cache, custom LRU).

### M2 — Data models
- **Typed model objects.** `Opportunity`, `Award`, `Recipient`,
  `Agency`, `PlaceOfPerformance` — plain Ruby classes (no
  ActiveRecord). Every object exposes `.to_h` (normalized hash) and
  `.raw` (original API JSON) so consumers are never locked into the
  gem's field selection.
- **Value-object lookups.** `Naics` (NAICS 2022, ~1100 entries with
  sector/subsector hierarchy), `Psc` (Product Service Codes), `SetAside`
  (SAM-codes normalized to Ruby symbols with human labels).
- **Agency normalization.** Canonical `Agency` value object with
  `code` / `name` / `cgac` / `aliases`. Resolves at ingestion — by the
  time the consumer sees an `Opportunity`, `#agency` is already a
  canonical instance, enabling fast indexed `WHERE agency_code = 'VA'`
  queries instead of fuzzy string matching. v0.1 ships ~35-40
  cabinet-level entries; consumers extend via
  `config.agency_aliases.merge!(...)`. Unknown agencies fall back to a
  raw-string `Agency` rather than raising. See [[domain/agency-normalization]].
- **Cross-referencing.** `Opportunity#related_awards` joins SAM
  opportunities to USASpending awards via agency + NAICS (PSC opt-in
  tightener) with a configurable ending-window for recompete detection.
  `Opportunity#likely_incumbent` returns the dominant recipient when
  there is one; returns `nil` when ambiguous (multi-award IDIQ) rather
  than forcing a guess. See [[domain/cross-referencing]].

### M3 — Ship it
- Recompete-detection example script (`examples/find_recompetes.rb`)
- README polish with full usage section
- RubyGems trusted-publishing release pipeline
- v0.1.0 tag + release
- Vindor dogfood migration (tracked as #30; executed in the Vindor repo)

## 4. What it does NOT do

Explicit non-goals. Every one of these has been considered and rejected
for v0.1.0; some are deferred (see §7), some are permanent boundaries.

**No persistence.** No ActiveRecord, no Sequel, no SQLite, no Postgres
adapter. The gem returns Ruby objects in memory. Consumers persist them
however they want.

**No web framework integration.** No Railtie, no Sinatra extension, no
Hanami integration. A Vindor-style consumer wires the gem into Rails
with five lines of initializer code; that's the right amount of glue.

**No scoring / ML / win probability.** That's the consumer's product IP.
The gem ends at "here's the data and the join." It does not score
opportunities, predict wins, or rank by fit.

**No user model.** No `User`, no `ContractorProfile`, no auth. Set-aside
eligibility predicates (`user_has_8a? && opp.set_aside == :sba_8a`)
live in the consumer.

**No scheduling.** No cron, no ActiveJob integration, no `every`. The
gem provides the methods (`Opportunity.modified_since(1.day.ago)`); the
consumer wraps them in jobs.

**No enrichment from non-SAM/non-USASpending sources.** No LinkedIn
scraping, no Crunchbase, no LLM-extracted scope from descriptions, no
news signals, no lobbying data, no CPARS past performance. Each of
those is a different problem domain with different data-quality
trade-offs; bundling them would explode the surface area.

**No UI.** No web dashboard, no CLI binary beyond a `bin/console`
helper. (A separate `contractkit-cli` gem might emerge later; not in
v0.1.)

**No alerting / notifications.** No email, no webhooks, no Slack
integration. The gem has no concept of "new since last time."

**No async I/O.** No `async` dep, no fiber-based clients, no
`concurrent-ruby`. Thread-safe for read; consumers who want parallel
fetches manage threads themselves.

The boundary rule: if it requires modeling a user, a tenant, a job
queue, or a persistent piece of state, it doesn't belong in the gem.

## 5. API surface

The six methods a user actually calls. Full reference in the README.

```ruby
# 1. Configure (one-time, global pattern)
Contractkit.configure do |c|
  c.sam_api_key = ENV.fetch("SAM_GOV_API_KEY")
  c.user_agent  = "MyApp/1.0 (ops@mycorp.com)"
end

# 2. Search opportunities (lazy Enumerable; pagination is transparent)
Contractkit::Opportunity.search(
  naics:     "541512",
  set_aside: :sba_8a,
  posted_after: Date.today - 30
).take(50)

# 3. Bulk pull for daily pipelines (block form, streams per record)
Contractkit::Opportunity.modified_since(1.day.ago) do |opp|
  MyApp::OpportunityIngest.upsert(opp.to_h)
end

# 4. Search awards
Contractkit::Award.search(
  agency: "Department of Veterans Affairs",
  naics:  "541512",
  awarded_after: Date.new(2023, 1, 1)
)

# 5. Cross-reference: the flagship feature
opp = Contractkit::Opportunity.find("FA8771-26-R-0042")
opp.related_awards        # Array of Award — likely related past work
opp.likely_incumbent      # Recipient or nil

# 6. Multi-tenant: instance client instead of global
client = Contractkit::Client.new(sam_api_key: tenant.sam_key)
client.opportunities.search(naics: "541512")
```

See [[design/data-models]] for the full model field-by-field reference
and [[domain/sam-gov]] / [[domain/usaspending]] for the API quirks the
gem hides.

## 6. v0.1.0 scope

Mapped to the 30 issues filed in [[ISSUES]] across four milestones.

| Milestone | Issues | Deliverable |
|---|---|---|
| **M0 Scaffolding** | #1-#7 | Gem skeleton, CI, RSpec/WebMock setup, YARD coverage gate, README v0, license/changelog/contributing |
| **M1 Core Clients** | #8-#15 | Error hierarchy, config, Faraday connection, rate limiter, SAM client, USASpending client, instrumentation hooks, opt-in cache |
| **M2 Data Models** | #16-#25 | Opportunity + parser, Opportunity resource methods, Award + parser, Award resource methods, Agency + alias table, NAICS, PSC, SetAside, CrossReference, PlaceOfPerformance |
| **M3 Ship It** | #26-#30 | Example script, README polish, RubyGems trusted publishing, 0.1.0 release, Vindor dogfood |

Critical path: #1 → #8 → #9 → #10 → #11 → #12 → #16 → #17 → #24 →
#26 → #27 → #29. Twelve serial issues. The rest parallelize.

Estimated effort: ~3-4 weeks solo, ~2-3 weeks with two contributors
splitting at the M2 branch point.

## 7. Future considerations

Deferred to later releases, explicitly **not committed**. Listed so
contributors know where the natural extension points are and can avoid
designing v0.1 in ways that close these doors.

- **Subtier agency normalization.** v0.1 covers cabinet-level only
  (~35-40 agencies). Subtier (contracting offices, sub-bureaus) is L-effort
  data-curation work and lives in v0.2.
- **Long-tail agencies.** NASA components, NSF, NIH sub-components,
  independent agencies. Coverage extends via the same `aliases.json`
  mechanism.
- **Subaward / sub-recipient data.** USASpending exposes it via
  `/api/v2/subawards/`; data quality is poor and the use cases are
  narrow. Deferred.
- **FPDS integration as a third source.** FPDS predates USASpending
  and offers some fields USASpending doesn't (e.g. detailed transaction
  history). Possible v0.3+.
- **Async / streaming clients.** A `Contractkit::Async` namespace using
  `async` for parallel fetches. Decision deferred until a real
  high-throughput consumer needs it.
- **Bulk download support.** USASpending's async `/bulk_download/`
  endpoint. Useful for civic-tech researchers; deferred until requested.
- **Grants.gov support.** SAM covers contracts only; grants live at
  grants.gov on a different API. Possible separate gem, possible v0.3
  expansion. Open question.
- **CLI binary** (`contractkit-cli` gem). Standalone tool for one-off
  queries. Separate gem to keep the core dep-free.
- **Rails Railtie.** Auto-loading config, generators. Only if a real
  Rails-shop consumer (other than Vindor) requests it. Vindor's
  five-line initializer is the current proof that it isn't needed.

## 8. Success criteria

Three concrete conditions for v0.1.0 to count as "shipped."

**1. Vindor migrates successfully.** Issue #30 (the dogfood) completes:
Vindor's `FetchOpportunitiesJob` / `FetchAwardsJob` HTTP code is
replaced by gem calls; `BuildContractsJob#extract` is deleted;
`EnrichContractsJob`'s Postgres JSONB join is replaced by
`Opportunity#related_awards`; Vindor's existing tests pass; a 7-day
parity sample shows no unexplained diffs. See
`vindor/docs/contractkit-migration.md` for the migration plan and
acceptance criteria.

**2. At least one external user installs and reports it works.** The
goal isn't 1000 users; it's *one* user outside Vindor running it in
production-shape conditions, surfacing the bugs that only show up
under foreign assumptions. "Reports it works" = a written sign-off,
not a download count.

**3. Test suite is hermetic.** `bundle exec rspec` passes on a fresh
checkout with no SAM.gov API key and no internet connection. WebMock
guards this in CI. If anyone runs the suite and it hits the real
network, that's a bug.

Two non-goals worth being explicit about:
- **Star count is not a success metric.** This isn't a viral gem; it's
  an infrastructure gem with a narrow audience.
- **Performance is not a v0.1 success criterion.** Correctness first.
  Tuning comes after a real consumer profiles real workloads.

---

## Open product decisions (PRD-level)

These are decisions the maintainer should land before or during v0.1
development. Each surfaces somewhere in the issue or design docs but
warrants product-owner attention rather than implementer judgment:

- **Repo public-launch trigger.** What's the bar to flip the repo from
  private to public? Proposed: v0.1.0 published to RubyGems +
  `⚠️ FILL IN` markers resolved + a 10-minute pass over docs for
  Vindor-specific language. (Currently private at
  `gudetimes1234/contractkit` per operator decision.)
- **Versioning policy for upstream API drift.** When SAM or USASpending
  silently change a field shape and the gem absorbs the change
  internally, is that a PATCH or a MAJOR? Lean PATCH if the gem's
  surface is unchanged. Lock in writing.
- **Set-aside encoding source of truth.** SAM's raw codes (`SBA`, `8A`,
  `WOSB`) as canonical, mapped to Ruby symbols via the gem's table —
  vs. some other normalization. Current call: SAM codes. Confirm.
- **Caching policy default.** Cache off by default in v0.1
  (currently the plan). Should it flip on for repeat lookups
  (NAICS/PSC/agency) in v0.2? Probably yes, but worth a thread.
