# contractkit Extraction Plan

> **Purpose:** Decide, component-by-component, what to lift out of Vindor's working code, what to rewrite from scratch, and what to leave behind, so that v0.1.0 of `contractkit` ships fast with the minimum useful surface.
>
> **Audience:** Maintainers scoping v0.1.0; Vindor engineers reading along as the dogfood consumer.

Related: [[../domain/sam-gov]], [[../domain/usaspending]], [[../domain/cross-referencing]], [[../domain/agency-normalization]], [[../contributing/architecture-overview]]

---

## Strategy in one paragraph

Vindor's working code is the right *learning material*, not the right *gem code*. The SAM.gov and USASpending HTTP plumbing in Vindor is wired directly into ActiveJob, ActiveRecord upserts, and a project-specific error namespace — extracting it literally would drag Rails and Postgres into the gem. The pragmatic move: **rewrite the two HTTP clients and the response parsers fresh on top of Faraday**, using Vindor's request shapes, field lists, pagination semantics, and error-class taxonomy as the spec. **Extract the field-mapping logic** out of `BuildContractsJob#extract` (it's pure functions on payload hashes — gem-ready as-is). **Skip everything below the parser line:** ActiveRecord models, jobs, schedulers, the matcher service, ActiveJob retries. Lookup tables (NAICS / PSC / set-aside / agency aliases) don't exist in Vindor yet — they ship as fresh `data/*.json` files in the gem and Vindor becomes their first consumer. Net effect: v0.1.0 is mostly green-field but informed by ~1,400 lines of battle-tested Vindor code, with one or two literal extractions (field mappers, error hierarchy shape) to avoid re-deriving things Vindor already got right.

---

## Component-by-component recommendations

| # | Component | Recommendation | Reasoning (short) | Effort | Milestone |
|---|---|---|---|---|---|
| 1 | SAM.gov API client | **Rewrite** | Vindor's lives inline in `FetchOpportunitiesJob`, hard-wired to `Net::HTTP` + Vindor's `Errors::SamGov::*`. Cleaner on Faraday with `Contractkit::Error::*`. | M | v0.1.0 |
| 2 | USASpending API client | **Rewrite** | Same shape as #1, inline in `FetchAwardsJob`. POST-body construction (FIELDS list, time_period filters) is worth copying verbatim. | M | v0.1.0 |
| 3 | Data normalization / transforms | **Extract** | `BuildContractsJob#extract` is already a pure function `Hash -> Hash`. Lifts cleanly into `Sam::ResponseParser`. | S | v0.1.0 |
| 4 | Agency name normalization table | **Rewrite (new)** | Vindor only has `agency_top = full.split(".", 2).first` — a heuristic, not a table. Real curated aliases are net-new work. See [[../domain/agency-normalization]]. | L | Later (v0.2.0) |
| 5 | NAICS code lookups | **Rewrite (new)** | Vindor only stores user-selected codes as strings. No lookup table exists. Ship a `data/naics_2022.json` from the official Census source. | M | v0.1.0 (data only) / v0.2.0 (rich API) |
| 6 | Set-aside type mappings | **Extract (light)** | Vindor reads `typeOfSetAsideDescription` and `typeOfSetAside` and stores raw. The *codes-to-labels* mapping is net-new but the field locations are extractable. | S | v0.1.0 |
| 7 | PSC code lookups | **Rewrite (new)** | Vindor doesn't use PSC at all. Pure greenfield from the GSA PSC manual. | M | Later (v0.2.0) |
| 8 | Cross-referencing (opp ↔ award) | **Extract (shape) + Rewrite (mechanism)** | The join key (`agency_top` + 6-digit NAICS + state) is solid IP. The implementation is a Postgres JSONB query — must be rewritten as an HTTP-based match in the gem. See [[../domain/cross-referencing]]. | M | v0.1.0 (basic) / v0.2.0 (full) |
| 9 | DB loading (AR models, migrations) | **Skip** | Gem has no DB. Vindor keeps these. | — | — |
| 10 | Scheduling / cron | **Skip** | Gem has no scheduler. Vindor keeps `ApplicationJob`, queue, cron triggers. | — | — |
| 11 | Error handling / retry logic | **Extract (taxonomy) + Rewrite (mechanism)** | Vindor's `Errors::*` hierarchy (Transient / RateLimit / Client / Malformed / Configuration) is exactly the right shape. The `retry_on` mechanism is ActiveJob-specific and must be rewritten as Faraday retry middleware. | S | v0.1.0 |
| 12 | Rate-limiting logic | **Rewrite (new)** | Vindor has none — it relies on SAM/USASpending tolerating its small daily quota. A token-bucket in Faraday is net-new but small. | S | v0.1.0 (opt-in) |
| 13 | Logging / instrumentation hooks | **Rewrite (new)** | Vindor logs via `ApplicationJob#log` + `Errors::Redactor`. Gem needs framework-agnostic `ActiveSupport::Notifications`-style instrumentation (or a plain block hook). Redactor concept is worth copying. | S | v0.1.0 |
| 14 | Test fixtures (VCR / sample JSON) | **Extract (capture fresh)** | Vindor has no captured fixtures dir (`test/fixtures/files` is empty). The *test patterns* (stubbing `fetch_page`) extract; the cassettes have to be recorded fresh against live APIs. | M | v0.1.0 |

---

## Extract details (what coupling to remove, where it lives)

### 3. Data normalization / transforms — `BuildContractsJob#extract`

**Lives in:** `/home/charlesgude/github/bidflow/vindor/app/jobs/build_contracts_job.rb` (lines 64–141).

**What's gem-worthy as-is:**
- `extract(payload)` — pure function over the SAM payload Hash. Maps `noticeId`, `title`, `fullParentPathName`, `naicsCode|naicsCodes[0]`, `typeOfSetAsideDescription|typeOfSetAside`, `solicitationNumber`, `links[0].href|uiLink`, `postedDate`, `responseDeadLine`, `pointOfContact[].fullName`, `placeOfPerformance.state` (both hash and string shapes).
- Two-shape tolerance for `placeOfPerformance.state` is real-world IP — keep it.
- `agency_top = full.split(".", 2).first` is the SAM-payload convention worth preserving (with a clearer name like `top_level_department`).

**Coupling to remove:**
- `string()` helper relies on `nil?` + `to_s.strip.empty?` — already framework-free. Move as-is.
- `parse_date` uses stdlib `Date.parse`. Fine.
- `parse_time` uses `Time.zone.parse` — **Rails-only**. Replace with `Time.iso8601` / `Time.parse` with explicit UTC handling.
- `value.blank?` is ActiveSupport. Replace with `value.nil? || value.to_s.strip.empty?`.
- `content_hash` belongs to the *consumer* (idempotency is a persistence concern). Drop from the gem.

**Target file:** `lib/contractkit/sam/response_parser.rb`, called from `Sam::Opportunities` after the HTTP layer.

### 6. Set-aside type mappings

**Lives in:** scattered references — `FetchAwardsJob::FIELDS` includes `"Type of Set Aside"`, `BuildContractsJob#extract` reads `typeOfSetAsideDescription`/`typeOfSetAside`. `User#set_aside_eligibility` carries human strings ("8(a)", "WOSB", "Full and Open") with no central enum.

**Coupling to remove:**
- No real coupling — the codes-to-labels table doesn't exist in Vindor. Build it fresh from SAM.gov's documented set-aside type codes (SBA, 8A, WOSB, EDWOSB, HZC, SDVOSBC, VSA, etc.) into `lib/contractkit/data/set_aside_codes.json`.
- Carry forward only the *field locations* (which JSON keys to read in SAM and USASpending payloads).

> ⚠️ FILL IN: Confirm whether Vindor's user-facing list of set-aside categories should be the canonical label set for the gem, or whether the gem should ship the SAM.gov codes verbatim and Vindor maps to its own labels.

### 8. Cross-referencing — opportunity ↔ award

**Lives in:** `/home/charlesgude/github/bidflow/vindor/app/jobs/enrich_contracts_job.rb` (lines 23–95).

**What's gem-worthy as-is:**
- The **join key**: `awarding_agency_top_level == opportunity.top_level_department AND substr(award.naics_code, 1, 6) == opportunity.naics6 AND award.place_of_performance_state_code == opportunity.state`. This triple is product IP. Keep it. See [[../domain/cross-referencing]].
- The **most-recent-2-awards** rule and the derived signals (`incumbent_name`, `last_award_amount`, `award_range_low/high`, `is_recompete`).

**Coupling to remove:**
- The query itself is a `RawAward.where("payload->>...")` — Postgres JSONB. Cannot be lifted; it presupposes a local DB of awards.
- The gem version is HTTP-driven: given an `Opportunity`, call `Usaspending::Awards.search(awarding_agency:, naics:, place_of_performance_state:, limit: 2, order: [...])` and synthesize a `CrossReference::Result`.
- `NotifyMatchedUsersJob.perform_later` — pure Vindor side effect, drop.
- `update_columns` — persistence, drop.

**Target file:** `lib/contractkit/cross_reference.rb` + `Opportunity#related_awards`, `Opportunity#likely_incumbent` model methods.

### 11. Error hierarchy

**Lives in:** `/home/charlesgude/github/bidflow/vindor/app/lib/errors.rb` (whole file, 70 lines).

**What's gem-worthy as-is:**
- The **shape**: a base `ApiError` carrying `(endpoint, http_method, params, status, response_snippet)`; subclasses `TransientApiError`, `RateLimitError`, `ClientApiError`, `MalformedResponseError`; a sibling `ConfigurationError` outside the `ApiError` tree.
- The **per-API namespacing** (`Errors::SamGov::RateLimitError < Errors::RateLimitError`) so callers can either rescue across all APIs or narrow to one. Carry this pattern into `Contractkit::Error::Sam::RateLimit < Contractkit::Error::RateLimit`.

**Coupling to remove:**
- The `Resend` namespace (Vindor's email vendor) — drop, out of scope.
- The `Errors::Redactor` reference at `ApiClient#loggable_params` — concept is good (redact API keys from log context), reimplement as `Contractkit::Http::Redactor` rather than copy verbatim (haven't read it).

**Target file:** `lib/contractkit/error.rb`.

### 14. Test fixtures — patterns

**Lives in:** `/home/charlesgude/github/bidflow/vindor/test/jobs/fetch_opportunities_job_test.rb`, `fetch_awards_job_test.rb` (not read in detail). `test/fixtures/files/` is empty.

**What's gem-worthy as-is:**
- The pattern of exposing `fetch_page` as a public method so tests can stub at that boundary instead of stubbing `Net::HTTP`. Translate to: expose `Sam::Client#raw_search` / `Usaspending::Client#raw_search` for VCR/WebMock to hook.
- The known edge cases discovered in production: duplicate notice IDs within a page, duplicate Award IDs at sort boundaries, two-shape `placeOfPerformance.state`. These deserve dedicated fixtures.

**Coupling to remove:**
- Vindor's tests upsert into `RawOpportunity` / `RawAward`. Gem tests should assert on parsed model objects directly.
- No actual JSON cassettes to lift — they have to be recorded fresh.

> ⚠️ FILL IN: Decide between VCR and WebMock+inline fixtures. VCR is friendlier for capturing real API drift; WebMock+inline keeps the spec suite hermetic and reviewable in PRs.

---

## Rewrite details (why fresh beats lifting)

### 1 & 2. SAM.gov and USASpending HTTP clients

Vindor's clients live inside `ApplicationJob` subclasses. They use `Net::HTTP` directly, format errors with Vindor's `Errors::*` namespace, and depend on ActiveJob for retries. Lifting them means dragging ActiveJob (or at minimum carving out a non-Job path). It's faster to rewrite ~120 LOC of HTTP code on Faraday, with the *request shapes* (URL, params, POST body for USAspending including the `FIELDS` array verbatim) copied as a spec. The `ApiClient` base in `app/lib/api_client.rb` is closer to gem-shaped, but it's still hand-rolled `Net::HTTP` and not worth the dependency-versus-Faraday argument.

**Important to copy verbatim from Vindor:**
- USASpending `FIELDS` list (20 fields, `FetchAwardsJob` lines 17–38) — this is a known-good selection that exercises the contract awards path.
- USASpending `CONTRACT_AWARD_TYPE_CODES = %w[A B C D]` filter.
- SAM `PTYPES = %w[p o]` (presolicitation + solicitation).
- SAM date format `%m/%d/%Y` (USASpending uses ISO8601 — they differ, easy to get wrong).
- USASpending pagination via `page_metadata.hasNext`; SAM via offset-until-empty.

### 4. Agency normalization

Vindor's "normalization" is one line: `agency_full.split(".", 2).first`. That's enough for a JOIN against USASpending's flat top-level agency strings but it doesn't handle the ~50 documented alias cases (Defense Logistics Agency vs DLA vs Department of Defense.Defense Logistics Agency, etc.). The gem needs a curated `data/agency_aliases.json` — that's research work, not extraction work. Defer to v0.2.0 unless a v0.1.0 consumer screams.

### 12. Rate limiting

Vindor doesn't rate-limit. SAM.gov publishes a 1000 req/hr key quota; USASpending is undocumented but tolerant. The gem needs a token-bucket so heavy consumers don't get keys revoked. Greenfield.

### 13. Instrumentation

Vindor logs via `ApplicationJob#log` and `log_progress` — Rails logger output. The gem must work in non-Rails contexts (plain Ruby script, Sinatra, Hanami). Use `ActiveSupport::Notifications` if available, otherwise a no-op block hook. Greenfield, but small.

---

## Skip details

### 9. Database loading

`RawOpportunity`, `RawAward`, `Contract` — all ActiveRecord models with content hashes, idempotency upserts, and the `needing_enrichment` scope. None of this belongs in the gem; per [[../contributing/architecture-overview]] the gem holds no state. Vindor keeps these as its **consumer layer** — it pulls `Contractkit::Opportunity` objects and persists them however it likes. This is exactly the dogfood case.

### 10. Scheduling

`FetchOpportunitiesJob`, `FetchAwardsJob`, `BuildContractsJob`, `EnrichContractsJob` are ActiveJob classes. Their *body* (after stripping persistence and retry plumbing) becomes gem method calls in the consumer. Their *scheduling* (queue, cron, retry attempts) is the consumer's concern.

---

## Risks, ordering, what could derail

### Ordering dependencies

1. **Error hierarchy first.** Everything else raises from it. Cheap, blocks nothing else if deferred but produces churn if added late.
2. **HTTP connection layer second.** Faraday + retry + redaction. Both API clients sit on it.
3. **SAM client + parser before USASpending.** SAM is simpler (GET, offset pagination, fewer fields) and lets us validate the parser pattern before doubling it.
4. **Cross-reference last.** Depends on having both APIs working and `Opportunity` / `Award` model APIs stable.
5. **Lookup tables (NAICS / PSC / agency aliases) on a parallel track.** Data-engineering work; no code dependency, can ship in v0.2.0 without blocking v0.1.0's core path.

### Risks

- **Vindor's payload coverage is narrow.** It uses 13 SAM fields and 20 USASpending fields. The gem should expose `.raw` on every model so consumers aren't blocked by gem field coverage — but the *normalized* surface in v0.1.0 will be Vindor-shaped, not API-complete. That's OK if documented.
- **USASpending POST body verbosity.** USAspending's `spending_by_award` endpoint requires explicit `fields` arrays. Changing the gem's "default fields" later is a breaking change. Make the field list explicit and configurable from day one.
- **Date format inconsistency.** SAM uses `MM/DD/YYYY`, USASpending uses ISO8601. The Vindor code gets this right but it's a paper-cut waiting to bite a contributor. Document loudly.
- **Set-aside semantics are not just strings.** Vindor's matcher (in `TieredContractMatcher`) treats set-asides as an eligibility predicate, not a label. The gem should at minimum expose the SAM code (`SDVOSBC`) AND the human label, and let consumers build the predicate. Don't bake Vindor's "Full and Open" sentinel into the gem.
- **Faraday version churn.** Faraday 2.x changed adapter registration and middleware. Pin a known-good version in the gemspec; document upgrade path.
- **VCR cassette decay.** SAM.gov and USASpending mutate their schemas without warning. Cassettes go stale. Plan a quarterly re-record ritual or accept that integration tests will yellow without notice.

### What could derail v0.1.0

- **Trying to ship #4 (agency aliases) and #7 (PSC) in v0.1.0.** Both are data-curation projects, not code projects, and will eat weeks. Defer.
- **Trying to support Ruby <3.1 to humor a downstream consumer.** Don't. The architecture overview pins 3.1+; hold the line.
- **Building a Rails Railtie because Vindor is Rails.** Vindor can wire the gem into Rails with five lines of initializer code. A Railtie locks the gem into Rails update cycles for no real benefit.

> ⚠️ FILL IN: Confirm whether Vindor's `Errors::Redactor` (referenced in `app/lib/api_client.rb` but not read in this pass) has logic worth lifting beyond "regex out API keys". If yes, add a #15 row above as **Extract**.

> ⚠️ FILL IN: Check whether Vindor has any working integration tests against live SAM/USASpending endpoints (not just stubbed unit tests). If yes, those test scenarios are direct input for the gem's `spec/integration/` plan.
