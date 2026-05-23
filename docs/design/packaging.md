# Packaging, CI, and Distribution

> **Purpose:** Define the repo scaffold, test strategy, CI pipeline, docs, versioning, release process, and license for `contractkit`.
>
> **Audience:** Maintainers preparing the v0.1 cut and contributors who need to know "where does this file go" / "how do I release".

Related: [[../contributing/architecture-overview]], [[../contributing/documentation-guide]], [[../domain/sam-gov]], [[../domain/usaspending]]

---

## Philosophy (one paragraph)

`contractkit` is packaged as a **small, boring, audit-friendly Ruby gem**. The dependency graph is shallow on purpose: `faraday` for HTTP and nothing else at runtime. CI runs offline against recorded fixtures so anyone — including someone without a SAM.gov key — can clone, `bundle`, and `bundle exec rspec` to green in under a minute. Releases are explicit, hand-cut from a human-edited `CHANGELOG.md`, signed off by a maintainer, and pushed via rubygems.org trusted publishing from GitHub Actions. We optimise for "predictable for a year" over "ergonomic for a week" — every dep, every CI job, every doc must justify the maintenance burden it adds.

---

## 1. Repo structure

The layout in [[../contributing/architecture-overview]] is correct for `lib/`. This section confirms it and fills in the project-root and tooling files around it.

```
contractkit/
├── lib/                                # see [[../contributing/architecture-overview]] for full tree
│   ├── contractkit.rb
│   └── contractkit/
│       └── ...                         # version, configuration, client, http/, sam/, usaspending/, models/, etc.
├── spec/
│   ├── spec_helper.rb                  # RSpec + VCR + WebMock config
│   ├── support/                        # shared examples, custom matchers
│   ├── fixtures/
│   │   ├── cassettes/                  # VCR-recorded HTTP responses (committed)
│   │   └── json/                       # hand-curated raw JSON for parser unit tests
│   ├── unit/                           # one file per lib/ source file
│   │   ├── configuration_spec.rb
│   │   ├── client_spec.rb
│   │   ├── sam/
│   │   ├── usaspending/
│   │   └── models/
│   └── integration/                    # full request → parsed model, gated behind ENV
├── docs/
│   ├── domain/                         # how the federal procurement world works
│   ├── contributing/                   # how to contribute to the gem
│   └── design/                         # this file lives here
├── examples/                           # runnable scripts; `ruby examples/list_opportunities.rb`
│   ├── list_opportunities.rb
│   ├── cross_reference_award.rb
│   └── README.md                       # explains how to set the API key envs
├── exe/                                # empty in v0.1; reserved for a future `contractkit` CLI
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                      # tests, lint, docs gate
│   │   └── release.yml                 # tag-triggered rubygems publish
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── dependabot.yml                  # bundler + actions; weekly
│   └── CODEOWNERS
├── .rspec
├── .rubocop.yml                        # extends rubocop-rspec, rubocop-performance
├── .yardopts                           # YARD output flags + included paths
├── Gemfile                             # `gemspec` line + dev-only group
├── Gemfile.lock                        # committed (we're a library AND we own the lockfile for dev parity)
├── Rakefile                            # default task = `spec rubocop yard`
├── contractkit.gemspec
├── README.md
├── CHANGELOG.md
├── LICENSE                             # MIT (see §7)
├── CODE_OF_CONDUCT.md                  # Contributor Covenant 2.1, unmodified
└── SECURITY.md                         # how to report vulns; private channel
```

**Gemfile.lock policy.** Libraries traditionally don't commit `Gemfile.lock`. We do, because the `Gemfile` resolves the gemspec plus dev tooling (rubocop, yard, vcr, rspec), and pinning those keeps CI reproducible. The gemspec is what's authoritative for consumers; the lockfile is dev-only.

**`exe/` reserved but empty.** No CLI in v0.1. Listed so contributors know where one would go later, and so the gemspec's `bindir = "exe"` line points somewhere stable.

> ⚠️ FILL IN: Decide whether to ship a `bin/console` (IRB with the gem loaded) and `bin/setup` (one-command bootstrap). `bundle gem` generates these; we likely want them but they're not required.

---

## 2. Testing strategy

### Three test categories

| Category | What it covers | Hits network? | Runs in CI? | Speed |
|---|---|---|---|---|
| **Unit** | Parsers, models, normalizers, configuration, pagination math, cross-reference logic | No (pure Ruby + JSON fixtures) | Always | <1s total |
| **Integration (cassette)** | Resource clients end-to-end with VCR replaying recorded responses | No (cassettes block real HTTP) | Always | ~5s total |
| **Live** | Real SAM.gov + USASpending.gov hits, used to refresh cassettes and smoke production | Yes | Manual only, never in default CI | minutes |

### Primary approach: VCR cassettes

VCR records real HTTP responses to YAML cassettes under `spec/fixtures/cassettes/` and replays them on subsequent runs. Combined with WebMock's `disable_net_connect!`, this gives us:

- **Zero network in CI.** Cassettes are committed; CI replays them. No SAM.gov key needed.
- **Realistic responses.** Cassettes are real upstream payloads, captured once. Easier to maintain than hand-rolled mocks.
- **Easy refresh.** A maintainer with a real key runs `VCR_RECORD=new_episodes bundle exec rspec spec/integration` to capture new fixtures.

`spec_helper.rb` sets:

```ruby
VCR.configure do |c|
  c.cassette_library_dir = "spec/fixtures/cassettes"
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.filter_sensitive_data("<SAM_API_KEY>") { ENV["SAM_GOV_API_KEY"] }
  c.default_cassette_options = { record: :none } # CI: replay only; never hit network
end

WebMock.disable_net_connect!(allow_localhost: true)
```

### Alternatives considered

| Approach | Pro | Con | Verdict |
|---|---|---|---|
| **VCR cassettes** (chosen) | Realistic, captured once, replays fast, zero CI network | Cassettes can drift from upstream silently | Primary |
| **WebMock stubs hand-written in specs** | Explicit; no fixture files | Maintenance burden scales with field count; fakes ≠ reality | Fallback for narrow cases (error paths, edge codes) |
| **Hand-curated JSON fixtures** in `spec/fixtures/json/` | Smallest, easiest to read | Drift; no end-to-end coverage of the Faraday stack | Used **only** for parser unit tests, not full request flow |
| **Standalone mock server** (e.g. Prism + OpenAPI) | Most accurate spec-level | Neither SAM.gov nor USASpending publishes a stable OpenAPI spec | Not viable today |
| **Live API tests in CI with a stored secret** | Catches upstream changes immediately | Burns rate limit; flakes; leaks key surface | No. Live tests are manual only. |

### Cassette hygiene

- Cassettes are reviewed in PRs like any other file. Reviewers check that no API key, no PII, and no transient `Date` headers leaked through.
- Filter rules in `spec_helper.rb` redact the SAM.gov key and any `Authorization` header.
- A cassette refresh is its own commit, with a one-line note in `CHANGELOG.md` under "Unreleased" if it changed observable test behavior.
- Cassettes for endpoints with notoriously volatile schemas (USASpending recipient profiles) get a comment at the top of the YAML noting when they were captured.

### No-key default

**A fresh clone with no env vars must run `bundle exec rspec` to a green suite.** This is a tested invariant: CI runs with no SAM.gov key set. Unit and integration tiers must both pass in that mode. Tests that need a key (the live tier) are tagged `:live` and skipped unless `ENV["CONTRACTKIT_LIVE_TESTS"] == "1"` and a key is present.

---

## 3. CI pipeline (GitHub Actions)

### Ruby matrix

Match upstream's still-supported MRI line. As of late 2025, that's 3.1, 3.2, 3.3, 3.4. Ruby 3.4 is the current stable. Drop 3.1 when its security support ends (per Ruby's policy, ~end of March 2027).

> ⚠️ FILL IN: Confirm the exact end-of-security-support dates for Ruby 3.1 and 3.2 at the time of v0.1 release, and document the gem's "drop a Ruby version" policy in `CHANGELOG.md` (likely: drop in a MINOR release, never a patch).

### Jobs

| Job | Purpose | Blocking? |
|---|---|---|
| `test` | RSpec across the Ruby matrix on Ubuntu | Yes |
| `lint` | RuboCop with our project config | Yes |
| `docs` | YARD build + undocumented-public-method gate | Yes |
| `audit` | `bundle audit` against the lockfile | Yes |
| `coverage` | SimpleCov upload (informational) | No |

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  test:
    name: RSpec (Ruby ${{ matrix.ruby }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        ruby: ["3.1", "3.2", "3.3", "3.4"]
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - name: Run RSpec (no network)
        env:
          CONTRACTKIT_LIVE_TESTS: "0"
        run: bundle exec rspec --format documentation

  lint:
    name: RuboCop
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - run: bundle exec rubocop --parallel

  docs:
    name: YARD coverage
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - name: Build YARD
        run: bundle exec yard doc --no-output
      - name: Fail on undocumented public methods
        run: |
          undoc=$(bundle exec yard stats --list-undoc | grep -E "^\s+\S+#" || true)
          if [ -n "$undoc" ]; then
            echo "Undocumented public methods:"
            echo "$undoc"
            exit 1
          fi

  audit:
    name: bundler-audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - run: bundle exec bundle-audit check --update
```

### RuboCop

We extend `rubocop`, `rubocop-rspec`, and `rubocop-performance`. No custom cops on day one. `.rubocop.yml` opts in to `NewCops: enable` so version bumps don't silently skip new rules.

### YARD coverage gate

The `docs` job fails if any public method, class, or module under `lib/` is missing a YARD doc. Threshold is binary (100% of public surface), consistent with [[../contributing/documentation-guide]]'s "every public method gets a YARD docstring" rule.

> ⚠️ FILL IN: If the gate proves too noisy on day one (e.g. data classes), introduce a `.yardopts`-level exclude for `Contractkit::Models::*` getters and document the carve-out here.

---

## 4. Documentation

### YARD config (`.yardopts`)

```
--markup markdown
--readme README.md
--no-private
--output-dir doc/api
--protected
-
docs/**/*.md
```

The trailing `-` separates source files from extra files; `docs/**/*.md` includes our domain and contributing docs in the rendered output so a reader hitting the API docs can click through to the "how the federal world works" material.

> ⚠️ FILL IN: Pick a YARD theme (default vs. yard-relax vs. yard-junk-output). Default is fine unless a maintainer wants nicer typography on rubydoc.info.

### README outline

The README is the gem's storefront. It must read credibly on day one — installation alone is not enough.

- **Banner** — gem name, one-line tagline ("A Ruby client for SAM.gov and USASpending.gov.").
- **Badges** — CI status, gem version, Ruby versions supported, license. Nothing aspirational; only badges that resolve on day one.
- **Why this exists** — One paragraph. Government procurement data lives in two APIs with inconsistent shapes, undocumented quirks, and no shared identifier; `contractkit` normalises both so Ruby apps can treat them as one source.
- **Installation** — `gem install contractkit` plus the `Gemfile` snippet, with Ruby 3.1+ floor noted.
- **Configuration** — Global `Contractkit.configure` block; mention `SAM_GOV_API_KEY` env var; note USASpending.gov needs no auth.
- **Quick start** — Three short examples a reader can copy verbatim: (1) search opportunities by NAICS, (2) look up an award by ID, (3) cross-reference an opportunity to historical awards.
- **Core concepts** — Brief: resources, models, lazy pagination, errors, caching. Each one-paragraph with a link to the relevant `docs/` file.
- **What it does not do** — Explicit non-goals: no persistence, no scheduling, no Rails integration, no LLM-flavoured enrichment. Mirrors [[../contributing/architecture-overview]] "What's deliberately not here".
- **Production notes** — Rate limits, retry behaviour, timeout defaults, what happens on a 429 or 5xx.
- **Compatibility** — Ruby version policy, upstream-API drift policy, SemVer commitments (links §5 below).
- **Roadmap** — Two or three bullets, dated by quarter, not by date. Linked to GitHub Milestones, not duplicated in prose.
- **Contributing** — One paragraph + link to `CONTRIBUTING.md`; mention the no-key test invariant and the cassette refresh workflow.
- **License** — One line + link to `LICENSE`.

A README that ships only with `gem install` and a single example reads as half-built. The above is the floor.

---

## 5. Versioning

### SemVer, applied to a normalisation library

We follow [SemVer 2.0](https://semver.org). MAJOR.MINOR.PATCH. The interesting question is what counts as breaking *for a normalisation library that sits between consumers and APIs we don't control*.

| Change | Verdict | Why |
|---|---|---|
| Rename a public method or argument | **Breaking (MAJOR)** | Consumer code references it directly. |
| Remove a public method | **Breaking (MAJOR)** | Same. |
| Rename a field on a normalized model (`Opportunity#posted_at` → `#posted_on`) | **Breaking (MAJOR)** | Consumer code references it directly. Normalized models are part of the public API. |
| Add a new field to a normalized model | **Non-breaking (MINOR)** | Pure addition. Consumers can ignore. |
| Change the type of an existing model field (e.g. `String` → `Date`) | **Breaking (MAJOR)** | Even if "more correct", existing callers break. |
| Change default behavior of a public method (e.g. default page size 25 → 100) | **Breaking (MAJOR)** | Behavioural contract change. |
| Add a new optional kwarg to a public method | **Non-breaking (MINOR)** | Existing callers unaffected. |
| Accommodate a non-breaking upstream API change | **Non-breaking (PATCH or MINOR)** | If the parser absorbs it transparently, PATCH. If a new field surfaces, MINOR. |
| Accommodate a **breaking** upstream API change that we can hide behind the existing public API | **Non-breaking (PATCH)** | The whole point of this gem is to absorb upstream churn. Internal rewrites that preserve our public contract are PATCHes. |
| Accommodate a breaking upstream API change that we **cannot** hide (e.g. SAM.gov drops a field we expose) | **Breaking (MAJOR)** | If we have to remove or change a field on a normalized model, that's a MAJOR even though the cause is external. We'll flag this in `CHANGELOG.md` with an `[upstream]` tag. |
| Drop a Ruby version from the support matrix | **Breaking (MAJOR)** | A consumer on the dropped Ruby can no longer upgrade us. |
| Add a Ruby version to the support matrix | **Non-breaking (MINOR)** | Pure addition. |
| Bump a runtime dep's minimum version (e.g. `faraday >= 2.8`) | **Breaking (MAJOR) if it could exclude a still-supported consumer**, otherwise MINOR. We'll document the rule of thumb: if the bumped dep version is older than 12 months, MINOR; otherwise MAJOR. |
| Tighten an error class hierarchy (e.g. `Contractkit::Error` → split into subclasses callers might rescue) | **Non-breaking** if existing rescues still catch; **breaking** if not. |

### Pre-1.0 caveat

While we're on `0.x`, MINOR is the breaking boundary (per SemVer §4). We will still try to follow the table above and bump MAJOR-style changes to the MINOR slot, with a clear `## [BREAKING]` callout in the changelog. Once we hit `1.0.0`, the table applies as written.

---

## 6. Release process

### Cadence and inputs

Releases are cut **on intent, not on a schedule.** A maintainer decides "enough has accumulated" and runs the release flow. There is no release train.

Inputs to a release:

1. `main` is green on CI.
2. `CHANGELOG.md`'s `## [Unreleased]` section has at least one user-visible entry.
3. The version bump in `lib/contractkit/version.rb` matches the §5 rules.

### Changelog: hand-edited

We keep [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, hand-edited, **not** auto-generated. Conventional Commits considered and rejected — for a low-velocity library with one or two maintainers, conventional-commit tooling adds rigidity without saving meaningful time, and auto-generated changelogs are notoriously thin. A human writes a sentence per user-visible change at PR-merge time.

PR template includes a "Changelog entry" field. Reviewers reject PRs that change user-visible behavior without a proposed line.

### The release flow

1. Maintainer opens a "Release vX.Y.Z" PR that:
   - Renames `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` in `CHANGELOG.md`.
   - Adds a fresh empty `## [Unreleased]` block above it.
   - Bumps `Contractkit::VERSION` in `lib/contractkit/version.rb`.
2. PR merges to `main` after normal review.
3. Maintainer tags the merge commit: `git tag -s vX.Y.Z -m "vX.Y.Z"` and pushes the tag.
4. `release.yml` workflow triggers on tag push, runs the test suite one more time, builds the gem, and publishes to rubygems.org via trusted publishing (OIDC, no long-lived API key in repo secrets).
5. Maintainer creates the GitHub Release pointing at the tag, body = changelog section for that version.

### `.github/workflows/release.yml` (shape)

Tag-triggered. Uses `rubygems/release-gem@v1` or equivalent action that exchanges the workflow's OIDC token for a one-time rubygems publish credential.

> ⚠️ FILL IN: Pin the exact rubygems trusted-publishing config (audience, repo allowlist) once we've registered the gem on rubygems.org. Until then, releases happen manually from a maintainer laptop with `gem push` against a hardware-key-protected account.

### Rake tasks

`Rakefile` exposes:

- `rake spec` — default test run.
- `rake rubocop` — lint.
- `rake yard` — build docs locally.
- `rake` — runs `spec rubocop yard` in order.
- No `rake release`. Releases go through the tagged-commit + Actions flow above; a local `bundle exec rake release` would skip CI and is deliberately omitted.

---

## 7. License

**MIT.** Short, permissive, ubiquitous in the Ruby ecosystem, no patent-grant clause to negotiate.

| Option | Pro | Con | Verdict |
|---|---|---|---|
| **MIT** | Familiar to every Ruby consumer; minimal friction for enterprise adopters | No explicit patent grant | Chosen |
| Apache 2.0 | Explicit patent grant; preferred by some large enterprises | Heavier; less idiomatic in Ruby; `NOTICE` file overhead | Not chosen |
| BSD-3-Clause | Similar permissiveness | No clear advantage over MIT for this gem | Not chosen |
| LGPL / MPL | Copyleft-lite | Friction for closed-source consumers; not a fit for a wrapper library | No |

### Government-data considerations

The data the gem fetches is U.S. federal procurement data, which is generally in the public domain under 17 U.S.C. §105 ("works of the United States government"). A few notes:

- The gem **wraps** the APIs; it does not redistribute their data. License-wise, this is no different from any other HTTP client.
- We do ship small static seed files (`naics_*.json`, `psc.json`, `set_aside_codes.json`, `agency_aliases.json`) derived from federal sources. These are public-domain inputs; our compilation of them is MIT-licensed alongside the rest of the gem.
- SAM.gov's terms of use cover *access* to the API (rate limits, no scraping). They do not restrict the licensing of a client library that obeys those terms. Worth a one-line note in the README under "Production notes" so adopters know to read the API ToS themselves.
- USASpending.gov data is explicitly designated public domain by the agency.

No unusual constraints. MIT is fine.

---

## Open questions

> ⚠️ FILL IN: `Gemfile.lock` policy — confirm we commit it. (Strong default: yes, for dev parity. Documented above; flagged here as a maintainer decision.)
>
> ⚠️ FILL IN: Whether to include a `.tool-versions` (asdf) or `.ruby-version` file. `.ruby-version` is the least controversial.
>
> ⚠️ FILL IN: Whether to enable SimpleCov coverage upload to a third party (Codecov, Coveralls) or just print to stdout in CI. Third parties add an account dependency.
>
> ⚠️ FILL IN: Trusted-publishing exact config on rubygems.org once the gem is registered (see §6).
>
> ⚠️ FILL IN: Whether `examples/` scripts are tested. Easiest path: a single CI step that runs each example with cassettes; deferred until `examples/` has more than a handful of files.
