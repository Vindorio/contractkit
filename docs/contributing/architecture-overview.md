# Architecture Overview

> **Purpose:** A lightweight map of the gem's internals so a new contributor can find what they need in under five minutes. Not a full architecture spec.
>
> **Audience:** First-time contributors; anyone returning after a long break.

Related: [[documentation-guide]], [[../domain/sam-gov]], [[../domain/usaspending]]

---

## One-paragraph mental model

`contractkit` is a thin aggregation layer over two read-only HTTP APIs (SAM.gov and USASpending.gov). Requests flow through a configured HTTP client to one of two API-specific resource clients, which return normalized model objects to the caller. Cross-referencing methods on those models trigger additional requests under the hood. The gem holds no state beyond configuration and an optional cache; it has no database, no scheduler, and no background workers.

## Directory layout (planned for v0.1)

```
contractkit/
├── lib/
│   ├── contractkit.rb                  # entry point; defines Contractkit module + .configure
│   ├── contractkit/
│   │   ├── version.rb                  # VERSION constant
│   │   ├── configuration.rb            # global config singleton
│   │   ├── client.rb                   # instance-based Client (wraps both APIs)
│   │   ├── error.rb                    # error class hierarchy
│   │   ├── http/
│   │   │   ├── connection.rb           # Faraday wrapper; retries, timeouts, logging
│   │   │   ├── rate_limiter.rb         # token-bucket pacing
│   │   │   └── cache_middleware.rb     # opt-in response cache
│   │   ├── sam/
│   │   │   ├── client.rb               # SAM.gov resource client
│   │   │   ├── opportunities.rb        # search, find, modified_since
│   │   │   └── response_parser.rb      # raw JSON → Opportunity model
│   │   ├── usaspending/
│   │   │   ├── client.rb               # USASpending resource client
│   │   │   ├── awards.rb               # search, find, updated_since
│   │   │   ├── recipients.rb           # recipient lookup
│   │   │   └── response_parser.rb      # raw JSON → Award model
│   │   ├── models/
│   │   │   ├── opportunity.rb          # SAM notice
│   │   │   ├── award.rb                # USASpending award
│   │   │   ├── agency.rb               # value object
│   │   │   ├── recipient.rb            # value object
│   │   │   ├── naics.rb                # value object + lookup
│   │   │   ├── psc.rb                  # value object + lookup
│   │   │   └── set_aside.rb            # value object + normalizer
│   │   ├── pagination/
│   │   │   ├── lazy.rb                 # Enumerable wrapper over both APIs' pagination
│   │   │   ├── sam_paginator.rb        # offset/limit
│   │   │   └── usaspending_paginator.rb # page/limit
│   │   ├── cross_reference.rb          # opportunity ↔ award matching logic
│   │   └── data/
│   │       ├── naics_2022.json         # static seed data
│   │       ├── psc.json                # static seed data
│   │       ├── set_aside_codes.json    # static seed data
│   │       └── agency_aliases.json     # curated normalization table
├── spec/
│   ├── spec_helper.rb
│   ├── fixtures/                       # VCR cassettes + raw JSON samples
│   ├── unit/
│   └── integration/
├── docs/                               # this directory
├── exe/                                # (no CLI in v1)
├── contractkit.gemspec
├── Gemfile
├── README.md
├── CHANGELOG.md
└── LICENSE
```

> ⚠️ FILL IN: Adjust once the actual layout settles. Anything above marked "planned" should be updated to match what's in `lib/` on disk after the first scaffold.

## The pipeline

A single read flows through these layers:

```
Caller code
   │  Contractkit::Opportunity.search(naics: "541512")
   ▼
Resource client                          (lib/contractkit/sam/opportunities.rb)
   │  builds query params; chooses paginator
   ▼
HTTP connection                          (lib/contractkit/http/connection.rb)
   │  Faraday request; retry middleware; rate limiter; optional cache
   ▼
External API                             (SAM.gov)
   │  JSON response
   ▼
Response parser                          (lib/contractkit/sam/response_parser.rb)
   │  normalizes fields; constructs Opportunity instances
   ▼
Pagination wrapper                       (lib/contractkit/pagination/lazy.rb)
   │  exposes Enumerable interface; defers next-page fetches
   ▼
Caller gets a lazy collection of Opportunity objects
```

## Where normalization happens

**One place per API:** `lib/contractkit/sam/response_parser.rb` and `lib/contractkit/usaspending/response_parser.rb`.

Both parsers are deliberately dumb. They translate raw JSON into model instances; they do not enrich, score, or call other APIs. Everything else — agency normalization, NAICS validation, cross-referencing — happens in the model layer or the `CrossReference` module.

This separation matters: parsers are easy to test against captured fixtures, and consumers can always escape to `.raw` if they need a field we didn't surface.

## Where configuration flows

```
Contractkit.configure { |c| c.sam_api_key = ... }
   │
   ▼
Contractkit::Configuration   (singleton, mutable, thread-safe via Monitor)
   │
   ├──> Contractkit.client  (lazy global Client built from Configuration)
   │       │
   │       └──> Contractkit::Sam::Client + Contractkit::Usaspending::Client
   │
   └──> Contractkit::Client.new(...)  (explicit instance; overrides global)
```

Two key invariants:

1. **Resource modules (`Contractkit::Opportunity`) delegate to the global client** by default. They are not classes with state — they're a convenience surface over `Contractkit.client.opportunities`.
2. **A `Contractkit::Client` instance is fully self-contained.** It carries its own configuration, its own connection, and its own cache instance. Multiple clients with different configs can coexist without interference.

## Where to look for what

| You want to... | Start here |
|---|---|
| Add a new SAM.gov filter | `lib/contractkit/sam/opportunities.rb` |
| Fix a field that comes back wrong | `lib/contractkit/{sam,usaspending}/response_parser.rb` |
| Add a normalized model field | `lib/contractkit/models/` + the relevant parser |
| Change retry behavior | `lib/contractkit/http/connection.rb` |
| Tune rate limits | `lib/contractkit/http/rate_limiter.rb` |
| Add a new cross-reference signal | `lib/contractkit/cross_reference.rb` |
| Update agency aliases | `lib/contractkit/data/agency_aliases.json` (no code change) |
| Add a NAICS or PSC entry | `lib/contractkit/data/{naics,psc}*.json` |
| Wire a new test API | `spec/fixtures/` + VCR config in `spec/spec_helper.rb` |

## Concurrency

The gem is **thread-safe for read**. Concrete commitments:

- `Contractkit::Configuration` access is guarded by a `Monitor`.
- Static lookup tables (`Naics`, `Psc`) are frozen at load.
- HTTP connections are per-client, not per-thread; Faraday handles thread safety internally.
- Lazy pagination iterators are **not** shared across threads. If you need parallel iteration, partition the query (e.g. by date window) and create one iterator per thread.

The gem does not spawn its own threads or fibers. If a caller wants parallelism, they manage it.

## What's deliberately not here

- **Database persistence.** No ActiveRecord, no Sequel, no SQLite. The gem returns objects; consumers persist them if they want to.
- **Scheduling.** No cron, no background workers, no `every`. Consumers wire the gem into Sidekiq, Rake, GoodJob, or whatever they already use.
- **Auth for end users.** The gem authenticates to upstream APIs; it does not know what a user is.
- **Web framework integration.** No Railtie in v1. (Possible later; not before consumer demand justifies it.)
- **Async I/O.** No `async` gem dependency. Threads or processes only.

These are intentional non-goals; revisiting any of them requires a design discussion before code lands.

## Open questions for the maintainer

> ⚠️ FILL IN: Pin a concrete HTTP library (`faraday` is the proposal). Check it against the Ruby version policy and dependency-minimalism goal.
>
> ⚠️ FILL IN: Decide whether `data/` JSON files are loaded eagerly at require-time or lazily on first access. (Eager is simpler; lazy is friendlier to one-off scripts.)
>
> ⚠️ FILL IN: Document the Ruby version floor (Ruby 3.1+ in the original scope doc — confirm and pin in gemspec).
