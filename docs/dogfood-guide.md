# Dogfood guide — migrating a Rails app to consume `contractkit`

> **Purpose:** Walk a Rails app maintainer through replacing bespoke
> SAM.gov and USASpending.gov integration code with the gem. Worked
> example uses Vindor — a Rails-based GovCon intelligence platform —
> as the consumer; the patterns generalize.
>
> **Companion docs:**
> - The Vindor-side rollout plan lives in `vindor/docs/contractkit-migration.md`
>   (in the Vindor repo) — it covers the 5-phase ship sequence and
>   risks specific to that codebase.
> - This guide is the gem-side reference any Rails app can follow.

---

## What you're migrating away from

The typical Rails-shop bespoke pattern looks like:

```ruby
# app/jobs/fetch_opportunities_job.rb
class FetchOpportunitiesJob < ApplicationJob
  retry_on Errors::SamGov::RateLimitError, wait: :exponentially_longer

  def perform(start_date:, end_date:)
    page = 0
    loop do
      response = fetch_page(start_date, end_date, page)
      break if response["opportunitiesData"].empty?
      response["opportunitiesData"].each do |notice|
        RawOpportunity.upsert(extract(notice), unique_by: :notice_id)
      end
      page += 1
    end
  end

  private

  def fetch_page(start_date, end_date, page)
    uri = URI("https://api.sam.gov/opportunities/v2/search")
    uri.query = URI.encode_www_form(
      api_key: ENV["SAM_GOV_API_KEY"],
      postedFrom: start_date.strftime("%m/%d/%Y"),
      postedTo:   end_date.strftime("%m/%d/%Y"),
      ptype: "p,o",
      limit: 1000,
      offset: page * 1000
    )
    response = Net::HTTP.get_response(uri)
    handle_status(response.code.to_i, response.body)
    JSON.parse(response.body)
  end

  def extract(notice)
    {
      notice_id: notice["noticeId"],
      title: notice["title"],
      agency_name: notice["fullParentPathName"]&.split(".", 2)&.first,
      naics_code: notice["naicsCode"].to_s.rjust(6, "0"),
      posted_at: Time.zone.parse(notice["postedDate"]),
      # ...30 more field mappings...
    }
  end

  def handle_status(status, body)
    # ...auth errors, rate-limit handling, malformed-response checks...
  end
end
```

A few hundred lines of HTTP plumbing, date-format conversions, error
handling, and field mapping. Across `FetchOpportunitiesJob`,
`FetchAwardsJob`, `BuildContractsJob#extract`, `EnrichContractsJob`,
and an `ApiClient` base class.

After migration, that becomes:

```ruby
class FetchOpportunitiesJob < ApplicationJob
  def perform(start_date:, end_date:)
    Contractkit::Opportunity.search(
      postedFrom: start_date,
      postedTo: end_date
    ).each_batch do |batch|
      RawOpportunity.upsert_all(batch.map(&:to_h), unique_by: :notice_id)
    end
  end
end
```

That's the goal.

## Step 1 — add the gem

```ruby
# Gemfile
gem "contractkit"
```

Then:

```bash
bundle install
```

The gem brings one runtime dependency (`faraday`, plus `faraday-retry`)
and works in Ruby 3.2+. No Rails coupling.

## Step 2 — configure once at boot

```ruby
# config/initializers/contractkit.rb
Contractkit.configure do |c|
  c.sam_api_key = ENV.fetch("SAM_API_KEY")
  c.user_agent  = "Vindor/#{Vindor::VERSION} (#{Rails.application.config.contact_email})"
  c.timeout     = 60
  c.retries     = 3
  c.logger      = Rails.logger
  c.cache       = Rails.cache
  c.cache_ttl   = 3600

  # Forward gem instrumentation into Rails' notifications bus.
  # (You'll also automatically get the events via AS::Notifications,
  # since the gem auto-detects AS — but the explicit block is more
  # discoverable and gives you per-tenant routing later.)
  c.on_event do |name, payload|
    Vindor::Telemetry.track(name, payload)
  end

  # Subtier coverage is v0.2; for the agencies your business cares
  # about that aren't in the cabinet-level seed, register aliases.
  c.agency_aliases.merge!(
    "NAVAL SEA SYSTEMS COMMAND"       => "DOD-NAVY",
    "USACE"                           => "DOD-ARMY",
    "CUSTOMS AND BORDER PROTECTION"   => "DHS-CBP"
    # ...your top 20 unmatched agencies
  )
end
```

If your env var is named something other than `SAM_API_KEY` (e.g.
Vindor's pre-existing `SAM_GOV_API_KEY`), set it explicitly. The gem
reads `SAM_API_KEY` from env automatically, but a one-line override
covers either case.

## Step 3 — replace the HTTP layer

Before:

```ruby
class FetchOpportunitiesJob < ApplicationJob
  # ...50 lines of HTTP, pagination, error handling, retry...
end
```

After:

```ruby
class FetchOpportunitiesJob < ApplicationJob
  def perform(start_date:, end_date:, naics: nil)
    Contractkit::Opportunity.search(
      ncode: naics,
      postedFrom: start_date,
      postedTo: end_date
    ).each_batch do |batch|
      RawOpportunity.upsert_all(
        batch.map { |opp| opp.to_h.merge(raw: opp.raw) },
        unique_by: :notice_id
      )
    end
  end
end
```

**What `each_batch` gives you:**

- One batch (Array of typed `Contractkit::Opportunity` objects) per
  upstream SAM page (default 1000 records per batch)
- Auto-pagination — the gem walks the offset/limit loop
- Memory cost is one batch at a time; pages are never accumulated
- Rate-limited and retried automatically by the gem's Faraday
  middleware

`.to_h` returns the gem's normalized hash (with `agency` /
`place_of_performance` nested-to-h'd). `.raw` exposes the original SAM
JSON for any field the gem doesn't surface — useful if you have AR
columns the gem's normalized hash doesn't cover.

Equivalent for awards:

```ruby
class FetchAwardsJob < ApplicationJob
  def perform(start_date:, end_date:, naics_codes:)
    Contractkit::Award.search(
      filters: {
        naics_codes: naics_codes,
        time_period: [{ start_date: start_date.iso8601, end_date: end_date.iso8601 }]
      }
    ).each_batch do |batch|
      RawAward.upsert_all(batch.map(&:to_h), unique_by: :award_id)
    end
  end
end
```

**Delete the bespoke HTTP + retry + auth-error-handling code.** All of
it. The gem owns those concerns now.

## Step 4 — adopt the typed model objects

Before, your AR layer probably had something like this:

```ruby
class RawOpportunity < ApplicationRecord
  # has columns: notice_id, title, agency_name, naics_code, posted_at, ...
end

class BuildContractsJob < ApplicationJob
  def perform(raw_opportunity)
    fields = extract(raw_opportunity.payload)  # ~80 lines of field mapping
    Contract.upsert(fields, unique_by: :notice_id)
  end

  private

  def extract(payload) = { notice_id: payload["noticeId"], ... }
end
```

After:

```ruby
class RawOpportunity < ApplicationRecord
  # Same columns, but the upsert source is now Contractkit::Opportunity#to_h
end

# BuildContractsJob is deleted entirely. Its job (mapping raw SAM
# fields into normalized columns) is what Contractkit::Sam::ResponseParser
# already does during the fetch.
```

You gain:

- **Canonical agency code as a column** for indexed queries
  (`WHERE agency_code = 'VA'` instead of `WHERE agency_name LIKE '%Veterans%'`).
  Add an `agency_code` column to your schema; populate from
  `opportunity.agency.code`.
- **Money as `BigDecimal`** end-to-end (Award#obligated_amount and
  #ceiling). Use AR's `decimal` column type, not float.
- **Set-aside as Ruby symbol** — store `opp.set_aside.to_s` in a string
  column, or convert to an enum if you prefer.

### Suggested AR column additions for the migration

| Column | Source | Purpose |
|---|---|---|
| `agency_code` (string, indexed) | `opp.agency.code` | Fast indexed agency filtering; `nil` for unmatched agencies |
| `agency_cgac` (string) | `opp.agency.cgac` | Cross-reference to other federal datasets keyed on CGAC |
| `set_aside_symbol` (string) | `opp.set_aside.to_s` | Ruby symbol form; lets the consumer enum on it |
| `naics_code` (string(6)) | `opp.naics_code` | Already zero-padded by the gem |

## Step 5 — replace cross-referencing

Before — Vindor's `EnrichContractsJob` ran a Postgres JSONB query to
find related awards:

```ruby
class EnrichContractsJob < ApplicationJob
  def perform(contract)
    related = RawAward.where(
      "payload->>'awarding_agency_top' = ? AND " \
      "substring(payload->>'naics_code' from 1 for 6) = ? AND " \
      "payload->>'place_of_performance_state' = ?",
      contract.agency_top, contract.naics6, contract.state
    ).order(...)
     .limit(2)

    incumbent = related.first&.recipient_name
    contract.update_columns(
      incumbent_name: incumbent,
      last_award_amount: related.first&.obligated_amount,
      # ...
    )
  end
end
```

After:

```ruby
class EnrichContractsJob < ApplicationJob
  def perform(opportunity)
    # opportunity is a Contractkit::Opportunity (typed), not an AR row
    related   = opportunity.related_awards(lookback: 3, limit: 5)
    incumbent = Contractkit::CrossReference.likely_incumbent(related)

    Contract.where(notice_id: opportunity.notice_id).update_all(
      incumbent_name:     incumbent&.name,
      incumbent_uei:      incumbent&.uei,
      last_award_amount:  related.first&.obligated_amount,
      related_awards_count: related.size
    )
  end
end
```

You're trading a Postgres JSONB join for an HTTP call to USASpending.
Mitigations:

- The gem's opt-in cache (`c.cache = Rails.cache`) deduplicates
  identical cross-reference queries within `cache_ttl` seconds.
- The gem's per-host rate limiter ensures a batch of 500 daily
  cross-references won't 429 USASpending.
- For very high-volume consumers, consider running the cross-ref pass
  off the daily-fetch path and persisting the result, rather than
  re-querying USASpending every time you read the opportunity.

## Step 6 — error handling

Before — a custom error hierarchy under `Errors::SamGov::*` /
`Errors::Usaspending::*`:

```ruby
retry_on Errors::SamGov::RateLimitError, wait: ->(e) { e.retry_after }
discard_on Errors::SamGov::AuthenticationError
```

After — same shape under `Contractkit::Sam::*` /
`Contractkit::Usaspending::*`:

```ruby
retry_on Contractkit::RateLimitError, wait: ->(e) { e.retry_after || 60 }
discard_on Contractkit::AuthenticationError
```

The gem's error classes carry the same diagnostic fields you're used
to (`endpoint`, `http_method`, `params`, `status`, `response_snippet`)
plus `retry_after` on rate limits. Rescue by the cross-API parent or
narrowly by source — both work.

## Step 7 — instrumentation

If you've been wiring custom telemetry around each HTTP call, replace
that with the gem's events:

```ruby
Contractkit.configure do |c|
  c.on_event do |name, payload|
    case name
    when "contractkit.request.finish"
      StatsD.timing("contractkit.#{payload[:url]&.split('/')&.last}.duration",
                    payload[:duration_ms])
    when "contractkit.rate_limit_wait"
      StatsD.increment("contractkit.rate_limit_wait",
                       tags: ["host:#{payload[:host]}"])
    when "contractkit.error"
      Sentry.capture_message("contractkit error: #{payload[:error_class]}",
                             extra: payload)
    end
  end
end
```

The same events also fire through `ActiveSupport::Notifications` when
AS is loaded — Rails subscribers work out of the box.

## Step 8 — parity check

Before deleting the old code permanently, run the new and old paths
side by side for at least a week:

1. Pick a fixed date window (e.g. 7 days)
2. Fetch with the old code path → `RawOpportunity` rows
3. Fetch with the new code path → a parallel `RawOpportunityV2` table
   (or just `to_h` to disk)
4. Diff field by field across both result sets

Acceptable diffs:

- Agency-name string changes (you now have canonical `agency.code`
  instead of raw agency strings — the rename is the win)
- Set-aside re-encoding (symbol vs string)
- Date precision (DateTime → Date for period fields)
- Money type (Float → BigDecimal)

Unacceptable diffs:

- Missing rows
- Missing fields not covered by `.raw`
- Money amounts that differ in value (not just type)
- Incumbent-name changes not traceable to a join-key reformulation

If you hit an unacceptable diff, file an issue against `contractkit`
with the specific record's `noticeId` / `award_id` and the diff. The
gem is small enough that we can address most "the new value is wrong"
reports inside a day.

## Step 9 — delete the old code

Once parity is signed off, delete:

- All custom SAM/USASpending HTTP clients
- All bespoke retry / rate-limit / error-mapping middleware
- The agency name-normalization heuristics (the gem owns this now)
- The `BuildContractsJob#extract` field-mapping table (the gem's
  parser is now the source of truth)
- Custom error classes that duplicate the gem's hierarchy
- The Postgres JSONB cross-reference query (replaced by
  `opportunity.related_awards`)

Pay attention to what you're NOT deleting:

- Scheduling: `FetchOpportunitiesJob.perform_later` still gets enqueued
  by cron / Sidekiq / GoodJob / etc. The gem doesn't schedule.
- Persistence: your AR models, migrations, content-hash idempotency,
  upserts — all yours. The gem returns typed objects; how you store
  them is your concern.
- Scoring / matching / win-probability / user workflow — all yours.

## Issues you might run into

| Issue | Fix |
|---|---|
| Agency unknown to the gem | `c.agency_aliases.merge!("YOUR STRING" => "YOUR-CODE")`. File an issue too — if it's a real agency the gem should ship it. |
| SAM field the gem doesn't surface | Read it from `opportunity.raw["fieldName"]`. File an issue to surface it as a typed field if it's worth shipping. |
| Set-aside code the gem doesn't recognize | The parser tolerates this (returns `:unknown` on `set_aside`); you can still read `set_aside_code` as the raw string. File an issue. |
| Date that fails to parse | The parser returns `nil` rather than raising. Read `raw` for the original string if you need it. |
| Test suite hits the real network | Pull `webmock` / `vcr` into the dev dep group and follow the recipes in `docs/contributing/documentation-guide.md` — cassettes for happy paths, WebMock for error paths. |
| You need a SAM endpoint other than search | v0.1 only ships the search endpoint. File an issue; the GET-by-noticeId is a small add. |

## Filing back to `contractkit`

The dogfood is two-way. As you find gaps:

1. Open an issue at `gudetimes1234/contractkit` with a Vindor-side
   reproducer (smallest possible).
2. Tag with the relevant area: `data-model`, `api-client`,
   `data` (for shipped lookup table gaps), etc.
3. If you have a fix in hand, PR welcome — see [../CONTRIBUTING.md](../CONTRIBUTING.md).

This is how the gem's coverage of long-tail agencies, NAICS codes,
and SAM quirks grows. The first consumer (you) is also the
highest-signal source of "what's actually broken in production."
