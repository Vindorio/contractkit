# Contributing to contractkit

Thanks for considering a contribution. The gem is pre-alpha and the surface
is small enough that even a tiny fix or doc clarification is worth a PR.

## AI Agents Quick Reference

If you're an AI coding agent working on contractkit, read these first:
- [`docs/contributing/architecture-overview.md`](docs/contributing/architecture-overview.md) — mental model
- [`docs/design/data-flow.md`](docs/design/data-flow.md) — Mermaid sequence/flow diagrams
- [`docs/design/model-relationships.md`](docs/design/model-relationships.md) — class diagram
- [`docs/design/endpoint-map.md`](docs/design/endpoint-map.md) — every API endpoint + params

Key conventions:
- **Test first** — every change ships with specs. VCR cassettes for happy paths, WebMock for error paths.
- **YARD docs on every public method** — `yard stats --list-undoc lib/` must report 100%.
- **No ActiveSupport in `lib/`** — runtime gem must work without Rails.
- **Frozen string literals** everywhere. RuboCop enforces.
- **British English** in comments/prose, US English in identifiers.
- **Never hit real network in tests.** Cassettes replay; WebMock guards.

## Getting set up

```bash
git clone https://github.com/gudetimes1234/contractkit.git
cd contractkit
bin/setup                # bundle install + any one-time prep
bundle exec rake         # spec + lint
```

You need:

- Ruby 3.2+ (the floor is enforced via the gemspec; bundler 4.x cannot
  install on 3.1).
- A C toolchain for native gems (`bigdecimal`, `nokogiri` transitively).
- For live integration testing only: a SAM.gov API key
  ([api.data.gov/signup](https://api.data.gov/signup/)) exported as
  `SAM_API_KEY`. **You do not need a key to run the unit suite** —
  cassettes replay deterministically.

## Development workflow

```bash
# 1. Create a branch
git checkout -b feature/my-change

# 2. Write your code + tests + YARD docs

# 3. Run the full suite (specs + lint)
bundle exec rake

# 4. Audit YARD coverage
bundle exec yard stats --list-undoc lib/

# 5. Commit (squash WIPs before opening PR)
git commit -m "Add: description of change"

# 6. Push and open PR
git push -u origin feature/my-change
```

## How to run things

| Command | What it does |
|---|---|
| `bundle exec rspec` | Run the test suite (replay-only; no network) |
| `bundle exec rspec spec/contractkit/agency_spec.rb` | Run a single spec file |
| `bundle exec rspec --tag vcr` | Run only VCR-backed specs |
| `bundle exec rake lint` | Run RuboCop |
| `bundle exec rake` | Both of the above |
| `bundle exec yard stats --list-undoc lib/` | Audit YARD coverage |
| `bundle exec yard doc` | Generate HTML docs into `doc/` |
| `gem build contractkit.gemspec` | Build the gem locally |
| `bundle exec ruby examples/basic_usage.rb` | Live end-to-end smoke test (needs `SAM_API_KEY`) |
| `bundle exec ruby examples/find_recompetes.rb` | Recompete-detection script (needs `SAM_API_KEY`) |
| `bundle exec ruby examples/query_idvs.rb` | IDV query + parent/child traversal (needs `SAM_API_KEY`) |
| `bundle exec ruby examples/query_transactions.rb` | Transaction history analysis (no key needed) |
| `bundle exec ruby examples/query_subawards.rb` | Subaward teaming patterns (no key needed) |
| `bundle exec ruby examples/query_entities.rb` | SAM entity enrichment (needs `SAM_API_KEY`) |

## What changes are welcome

- Bug fixes (always — open an issue or just send a PR with a regression spec).
- New shipped data: extending `lib/contractkit/data/agency_aliases.json`,
  `naics_2022.json`, `psc.json`, or `set_aside_codes.json` with codes you've
  hit in the wild that the gem didn't recognize. Drive-by additions welcome.
- Docs improvements: README clarifications, fixing examples, expanding
  `docs/domain/*.md` with real-world quirks you've observed.
- New features: please open an issue first so we can scope it before you
  spend time. v0.2 is not yet planned in detail.

## What changes are deferred to v0.2

Already-scoped follow-ups (don't duplicate work on these without coordinating):

- Full NAICS 2022 coverage (~1100 codes) — currently shipping ~40
- Full PSC coverage (~5000 codes) — currently shipping ~25
- Sub-tier agency normalization (DoD service branches, DHS components,
  etc.) — currently shipping cabinet-level only
- `Award.find` via USASpending's `/api/v2/awards/{id}/` endpoint (needs
  a second parser path)
- Subaward / sub-recipient data
- Async / streaming clients

## Coding conventions

- **YARD docs on every public class and method.** CI does NOT yet enforce
  this (we trust the reviewer), but `yard stats --list-undoc lib/` should
  report 100% coverage. See [docs/contributing/documentation-guide.md](docs/contributing/documentation-guide.md).
- **RuboCop with the project config** — no exceptions without a per-line
  `# rubocop:disable` and a short rationale comment. The default-on cops
  cover the right things.
- **Tests for every change.** See [docs/design/packaging.md](docs/design/packaging.md)
  §Testing strategy. Briefly: VCR cassettes for happy paths against the
  real APIs (recorded once and committed); WebMock for error paths and
  edge cases that are hard to trigger live. The `:vcr` metadata picks
  the right one.
- **British English in comments and prose**, US English in identifiers
  (matches existing convention).
- **Frozen string literals everywhere** (enforced by RuboCop).
- **No `ActiveSupport::` in `lib/`.** AS is fine as a test dev-dep but
  the runtime gem must work without it.

## Spec layout

Specs mirror the lib layout:

```
spec/
  contractkit/
    agency_spec.rb              # unit
    sam/client_spec.rb          # integration (VCR-backed)
    http/connection_spec.rb     # middleware unit
    ...
  fixtures/
    cassettes/                  # committed VCR cassettes; never contain secrets
  meta/
    no_real_http_guard_spec.rb  # asserts the no-network posture
    vcr_replay_spec.rb          # asserts VCR is wired correctly
```

## Test patterns

Three categories of tests, each with a distinct strategy:

### Unit tests (`spec/contractkit/*_spec.rb`)

Test parsers, models, normalizers, value objects, pagination logic.
Pure Ruby — no network, no VCR. Use hand-curated JSON fixtures for
parser tests.

```ruby
# Agency normalization: unit, no network
RSpec.describe Contractkit::Agency do
  describe ".normalize" do
    it "matches known agency by code" do
      result = Contractkit::Agency.normalize("VA")
      expect(result.code).to eq("VA")
      expect(result.name).to eq("Department of Veterans Affairs")
    end
  end
end
```

### Integration tests (`spec/contractkit/sam/client_spec.rb`, etc.)

Test full request → parsed model flow using VCR cassettes. Tagged
`:vcr` in specs.

```ruby
# Client search: integration, VCR replay
RSpec.describe Contractkit::Sam::Client, :vcr do
  it "returns parsed opportunities" do
    results = Contractkit::Opportunity.search(ncode: "541512").first(3)
    expect(results.first).to be_a(Contractkit::Opportunity)
  end
end
```

### Live tests (manual only, never in CI)

Require `SAM_API_KEY` and `CONTRACTKIT_LIVE_TESTS=1`. Used only to
record fresh cassettes and smoke-test against production APIs.

```bash
SAM_API_KEY=*** VCR=new_episodes bundle exec rspec spec/contractkit/sam/client_spec.rb
```

### Adding a new resource model (checklist)

When adding a new model (like `Contractkit::Idv`), follow this order:

1. **Write the model class** (`lib/contractkit/idv.rb`)
   - Plain Ruby value object with `attr_reader`, `initialize`, `to_h`
   - `==` / `hash` by identity field
   - YARD docs on every public method

2. **Extend the API client** (`lib/contractkit/usaspending/client.rb`)
   - Add the raw HTTP method (e.g., `#raw_idv_search`)

3. **Write the response parser** (in the appropriate `response_parser.rb`)
   - Pure function: raw JSON → model instances
   - Nil-safe everywhere
   - `.raw` on every model

4. **Add resource-level methods** (`.search`, `.find`, etc.)

5. **Register in the main entry point** (`lib/contractkit.rb`)
   - Add `require_relative`

6. **Write specs**
   - Parser unit tests with hand-curated JSON fixtures
   - Client integration tests with VCR cassettes
   - Error-path tests with WebMock stubs

7. **Add domain docs** (`docs/domain/<new-model>.md`)

8. **Add an example script** (`examples/query_<new-model>.rb`)

9. **Update the README data model reference table**

### Adding shipped data entries

When extending lookup tables (`agency_aliases.json`, `naics_2022.json`,
`psc.json`, `set_aside_codes.json`):

1. Add the entry to the JSON file
2. Add a corresponding spec that exercises the new entry
3. No code change needed — the lookup classes read the JSON at load time
4. Note the addition in CHANGELOG.md under `## [Unreleased]`

## Recording / refreshing VCR cassettes

```bash
SAM_API_KEY=<your-key> VCR=new_episodes bundle exec rspec spec/<path>
```

`VCR` env values:

- `none` (default) — replay only; raise on unknown requests
- `new_episodes` — replay matched, record new
- `all` — re-record everything (use sparingly; expensive on the rate limit)
- `once` — record if cassette is empty; replay otherwise

After recording, **always verify cassettes contain no real API key**:

```bash
grep -rn "SAM-[0-9a-f]\{8\}-" spec/fixtures/cassettes/   # must be empty
```

The `spec_helper.rb` configures VCR's `filter_sensitive_data` to mask
the `SAM_API_KEY` env var to `<SAM_API_KEY>` before writing, plus a
custom `:uri_ignoring_api_key` matcher so cassettes replay regardless of
whether the env var is set in CI.

## Pull request expectations

- One issue per PR. Stack PRs if the work naturally splits.
- Commits should be in a coherent narrative order — squash WIP commits
  before opening for review.
- New behaviour ships with specs in the same commit.
- `bundle exec rake` passes locally before you push.
- If you touched docs and there's a corresponding doc in `docs/domain/`
  or `docs/design/`, update both.

## Reporting bugs

Open an issue with:

1. Minimal Ruby reproducer (10 lines or less ideally)
2. What you expected
3. What happened
4. `Contractkit::VERSION`, Ruby version, `bundle env` excerpt

If the issue involves a specific SAM or USASpending response shape,
**include the raw JSON** (with your API key redacted) — that's far more
useful than a description. The gem's `Opportunity#raw` /
`Award#raw` give you exactly this.

## Code of conduct

Be kind. Government data is dry; the people working with it deserve
better than typical OSS shouting matches.

## Release process

(For maintainers — see [docs/design/packaging.md](docs/design/packaging.md)
§Release process for the full flow.)

1. Bump `lib/contractkit/version.rb`
2. Move `[Unreleased]` entries under a new dated header in `CHANGELOG.md`
3. Open a PR; merge to `main`
4. Tag `v<x.y.z>` and push the tag; `.github/workflows/release.yml`
   takes over via RubyGems trusted publishing (OIDC; no API key in CI
   secrets — must be configured once on rubygems.org's dashboard)
