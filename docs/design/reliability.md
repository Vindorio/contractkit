# Reliability Layer

> **Purpose:** How `contractkit` stays well-behaved against two upstream APIs that disagree on rate limits, key requirements, response shape, and timeout behavior. This is the design for retries, pacing, key handling, caching, logging, and timeouts.
>
> **Audience:** Contractkit contributors building or maintaining `lib/contractkit/http/*` and the resource clients.

Related: [[sam-gov]], [[usaspending]], [[architecture-overview]]

---

## Design principles

1. **Sane defaults, opt-in advanced behavior.** Out of the box, the gem retries transient failures and paces SAM at a safe rate. Caching, custom retry policies, and bursty modes are opt-in.
2. **No external runtime dependencies.** No Redis, no `concurrent-ruby`, no Sidekiq. Token-bucket pacing and the cache are in-process. Distributed coordination is the consumer's problem.
3. **Per-client isolation.** Reliability state (token bucket, cache, logger) is owned by a `Contractkit::Client` instance, not by global mutable state. Two clients with two SAM keys do not share a bucket.
4. **Fail loud, log quietly.** Programmer errors (missing SAM key, malformed config) raise on first SAM call. Data-quality oddities are normalized silently and noted at `debug`/`warn`.
5. **The two APIs are different and the gem reflects that.** A single retry/rate-limit policy across both APIs would be wrong in both directions.

---

## 1. Rate limiting

### What we're working against

| API | Documented | Observed | Default the gem ships |
|---|---|---|---|
| SAM.gov | 60 req/min (public tier) | ~20 req/min sustained, bursts 30-40 ok | **20 req/min** |
| USASpending | none | ~10-15 req/sec, 503s past 10 parallel | **5 req/sec** |

Source: [[sam-gov]] §rate-limits, [[usaspending]] §rate-limits.

### Algorithm: in-process token bucket

A token bucket keyed by API (one bucket per `Sam::Client`, one per `Usaspending::Client`). Refill is lazy — we compute available tokens on each request from `(now - last_refill) * rate`, no background thread.

```ruby
# Sketch — lib/contractkit/http/rate_limiter.rb
class RateLimiter
  def initialize(rate_per_second:, burst:)
    @rate    = rate_per_second
    @burst   = burst
    @tokens  = burst.to_f
    @last    = monotonic_now
    @mutex   = Mutex.new
  end

  def acquire
    @mutex.synchronize do
      refill
      if @tokens >= 1
        @tokens -= 1
        return 0.0
      end
      wait = (1 - @tokens) / @rate
      @tokens = 0
      wait
    end.then { |s| sleep(s) if s > 0 }
  end
end
```

Why a `Mutex` (not `Monitor`, not lock-free): the bucket is touched once per request and held for microseconds. Contention is bounded by the rate itself.

### Why not a leaky-bucket, sliding window, or AIMD?

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| Token bucket (chosen) | Simple, allows configured bursts, no background thread | Has to be tuned per-API | Ship it. |
| Sliding window counter | Strictly enforces "N per minute" | Allocates per-request, harder to reason about across threads | No — extra memory for no win. |
| AIMD (additive-increase, multiplicative-decrease) | Adapts to 429s automatically | Stateful, hard to test, surprising in dev | Defer. Revisit if 429s become common after launch. |
| Off-process (Redis) | Cross-process coordination | New dep, deployment friction | Out of scope. Document as an extension point — see below. |

### Configuration

```ruby
Contractkit.configure do |c|
  c.sam.rate_limit          = 20  # per minute (default 20)
  c.sam.rate_limit_burst    = 5   # tokens (default 5)
  c.usaspending.rate_limit  = 5   # per second (default 5)
  c.usaspending.rate_limit_burst = 5
end
```

Setting `rate_limit = nil` disables pacing for that API. Useful for tests and for callers who run their own external limiter (e.g. a job queue with concurrency caps).

### Multi-process / multi-host

Out of scope for v1. The `RateLimiter` is per-process. Callers running the gem in N parallel workers should set `rate_limit / N` per worker, or implement their own external limiter and disable ours. We document this in the README, not the gem.

> ⚠️ FILL IN: Confirm whether Vindor runs the pipeline as a single process today (then per-process bucket is fine) or as parallel workers (then per-process needs division).

### Handling 429s when they happen anyway

The token bucket is preventive. Real 429s still occur during quota resets, key changes, or upstream changes. The retry middleware handles 429 specifically — see §2.

---

## 2. Retries

### Strategy

Exponential backoff with full jitter, **only for idempotent verbs** (`GET`, and the POSTs to `/search/spending_by_award/` and similar which are read-only-by-convention).

| Trigger | Retry? | Max attempts | Backoff | Notes |
|---|---|---|---|---|
| `Errno::*`, connection refused | yes | 3 | 0.5s, 1s, 2s + jitter | Network blip |
| `Net::OpenTimeout` (connect) | yes | 3 | same | Connect timeout |
| `Net::ReadTimeout` (read) | yes | 2 | 1s, 3s + jitter | Be more conservative — real work may have happened |
| HTTP 500, 502, 503, 504 | yes | 3 | 1s, 3s, 9s + jitter | Server-side transient |
| HTTP 429 | yes | 3 | honor `Retry-After`, fallback to 30s | See below |
| HTTP 408 | yes | 2 | 1s, 3s | Rare; treat like 504 |
| HTTP 4xx (other) | **no** | — | — | Client errors don't fix themselves |
| `Net::HTTPFatalError` parsing | no | — | — | Malformed response — fail loud |

### 429 handling

On 429:
1. Read `Retry-After` (seconds or HTTP-date). If present, sleep that long.
2. If absent, sleep 30s (a deliberate over-correction; SAM's edge tends to clear quickly but the daily quota is a real thing).
3. Decrement the token bucket aggressively (drain it) so concurrent requests in the same process don't pile on.
4. Retry up to 3 times. After that, raise `Contractkit::RateLimitError` with `retry_after` and the original response attached.

> ⚠️ FILL IN: Have you ever seen SAM return a `Retry-After` header value worth honoring, or is it always missing? The 30s fallback assumes it's missing.

### Configuration

```ruby
Contractkit.configure do |c|
  c.retries.enabled       = true   # default
  c.retries.max_attempts  = 3      # default
  c.retries.base_interval = 1.0    # seconds
  c.retries.max_interval  = 30.0
end
```

Per-call override is supported via `Contractkit::Client.new(retries: {max_attempts: 0})` for the rare "one shot, no retries" case (typically in tests).

### Why Faraday's `retry` middleware isn't quite enough

We use `faraday-retry` as the substrate but wrap it. Reasons:

- `faraday-retry` doesn't drain the local token bucket on 429 — we want that.
- We want structured logging of every retry attempt at `info` level (see §6), not Faraday's default `debug`-only behavior.
- We want to attach the original `Faraday::Response` to our `RateLimitError` so the caller can read `Retry-After`.

So: `Contractkit::Http::RetryMiddleware` is a thin Faraday middleware that calls into `faraday-retry`'s policy logic but owns the logging, error wrapping, and bucket-draining.

### What is NOT retried

- Any 4xx other than 408/429. (`401 AuthenticationError`, `404 NotFoundError`, `422` validation, `400` bad filters.)
- JSON parse failures (`Contractkit::Error` subclass `MalformedResponseError`).
- Anything the caller explicitly disables.

---

## 3. API key management

### Two different stories

| API | Key required? | Where it goes | Default behavior on missing |
|---|---|---|---|
| SAM.gov | Yes | `?api_key=` query param | Raise `Contractkit::AuthenticationError` on first SAM call |
| USASpending | No | — | No-op |

### Fail-fast or lazy?

**Lazy**: validate when SAM is actually called, not when `Contractkit.configure` runs. Reasons:

- A consumer using only USASpending should be able to load the gem without a SAM key.
- `Contractkit.configure` is sometimes called in Rails initializers where ENV may not be fully loaded yet (Spring, foreman edge cases).
- The error is unambiguous when it happens — the trace points at the SAM call site, not a config block.

The validation is a single check at the top of `Contractkit::Sam::Client#request`:

```ruby
raise Contractkit::AuthenticationError, "SAM.gov API key not configured. Set Contractkit.config.sam.api_key or pass api_key: to Client.new." if @api_key.nil? || @api_key.empty?
```

### Key rotation

The gem does not own rotation. We do support:

- **Per-client keys** via `Contractkit::Client.new(sam: {api_key: "..."})`. Useful for multi-tenant Rails apps that resolve a tenant's key from a database column.
- **Re-reading from a callable** if `api_key` is set to a `Proc` / lambda:

```ruby
Contractkit.configure do |c|
  c.sam.api_key = -> { AwsParameterStore.get("/contractkit/SAM_KEY") }
end
```

The Proc is invoked per-request. Cheap callers can return a memoized string; rotation-aware callers can invalidate their memo on a timer.

### Expiry warnings

api.data.gov doesn't include an explicit "your key expires in N days" header. Closest signals:

- A 401 with the body `{"error": {"code": "API_KEY_INVALID"}}` — surface as `AuthenticationError`, message includes the upstream code.
- A 429 with `X-RateLimit-Remaining: 0` and `X-RateLimit-Reset` — log at `warn`, attach to `RateLimitError`.

> ⚠️ FILL IN: Has Vindor ever observed api.data.gov returning a soft-expiry warning header (e.g. `X-Api-Key-Expires-In`)? If so, the gem should log it at `warn`.

### Secret logging

Never log the full URL with `api_key=...` in the query string. The HTTP logging middleware (§6) redacts via a regex before any log emission:

```ruby
SECRET_PARAMS = %w[api_key].freeze
def sanitize(url)
  uri = URI(url)
  return url unless uri.query
  q = URI.decode_www_form(uri.query).map { |k, v| [k, SECRET_PARAMS.include?(k) ? "[REDACTED]" : v] }
  uri.dup.tap { |u| u.query = URI.encode_www_form(q) }.to_s
end
```

Applied at the boundary in `Contractkit::Http::LoggingMiddleware#sanitize_url`. There is one place that does this; everywhere else logs the sanitized form.

---

## 4. Data quality

The gem cleans silently for known-and-documented quirks (where the cleaning is unambiguous). It logs at `warn` when it encounters something unexpected. It never raises on a single bad record — partial data is more valuable than no data.

| Quirk | Where handled | Behavior | Surface? |
|---|---|---|---|
| SAM `placeOfPerformance.state` polymorphism (string vs hash) | `sam/response_parser.rb` | Coerce to string | Silent |
| SAM `naicsCode` as integer | `sam/response_parser.rb` | Cast to 6-char zero-padded string | Silent |
| SAM `responseDeadLine` (note the typo) | `sam/response_parser.rb` | Map both `DeadLine` and `Deadline` to `response_deadline_at` | Silent, but future-proof |
| SAM `postedDate` timezone drift | `sam/response_parser.rb` | Default to ET when no offset | Log at `debug` |
| Agency name inconsistency across SAM/USASpending | `models/agency.rb` via `data/agency_aliases.json` | Normalize through alias table | Log at `debug` on alias hit; `warn` on unknown agency |
| USASpending `limit > 100` silent cap | `usaspending/awards.rb` | Cap input at 100, log at `warn` | Warn — caller's expectation is wrong |
| Missing required `fields` on USASpending search | `usaspending/awards.rb` | Inject default field set | Silent |
| Unrecognized notice `type` value | `sam/response_parser.rb` | Pass through, set `notice_type` to raw string | Log at `warn` |
| Unrecognized set-aside code | `models/set_aside.rb` | Pass through, `label = nil` | Log at `warn` |
| JSON missing expected key | `*/response_parser.rb` | Field becomes `nil` | Log at `debug` with field name |

### The principle

Parsers are dumb (per [[architecture-overview]] §normalization). They translate known-shape JSON into models. Cleaning rules above are documented in code comments next to the cleaning, with a link to the relevant section of [[sam-gov]] / [[usaspending]].

If a parser hits something it cannot interpret (e.g. `naicsCode` is a hash), it logs at `warn`, sets the field to `nil`, and continues. The raw JSON is always available via `Opportunity#raw` so the caller can recover.

> ⚠️ FILL IN: Are there Vindor-specific data-quality patches in the existing Python pipeline (`vendor_pipeline/transform_with_polars.py`) that we should port? Audit and list here.

---

## 5. Caching

### Default: off

Caching is opt-in. Reasons:

- Most callers (Rails apps, ETL jobs) already have their own caching layer (Rails.cache, a database, parquet files). Layering a second cache silently is worse than no cache.
- A stale cache for federal contract data is sometimes harmful (a missed solicitation amendment, a stale award amount). The caller should decide what's safe.

### When enabled

The cache is pluggable. Any object responding to `#read(key)` and `#write(key, value, ttl:)` works. `Rails.cache` works out of the box. So does `ActiveSupport::Cache::MemoryStore` for one-off scripts.

```ruby
Contractkit.configure do |c|
  c.cache         = Rails.cache       # or MyCache.new
  c.cache_ttl     = 300               # default 5 minutes
  c.cache_strategy = :read_through    # :read_through | :stale_if_error | :off
end
```

### What's cacheable

| Endpoint | Cacheable? | Default TTL | Notes |
|---|---|---|---|
| SAM `/opportunities/v2/search` | yes | 5 min | Listing data. Acceptable staleness. |
| SAM `/opportunities/v2/{noticeId}` | yes | 1 hour | Individual notice; changes rarely. |
| USASpending `/search/spending_by_award/` | yes | 1 hour | Historical data, slow-moving. |
| USASpending `/awards/{id}/` | yes | 6 hours | Even slower. |
| USASpending `/references/naics/` | yes | 24 hours | Practically static. |
| Anything that mutates | n/a | — | Gem makes no mutating requests. |

### Cache key strategy

```
contractkit:v1:{api}:{endpoint}:{sha1(canonical_request)}
```

Where `canonical_request` is `verb + path + sorted_query_or_body_json`. The API key is **not** part of the key — two clients with different keys for the same query should share a cache entry. The cache key is per-version (`v1`) so we can invalidate on gem upgrades by bumping the prefix.

```ruby
def cache_key(req)
  body = req.body ? JSON.generate(sort_recursive(JSON.parse(req.body))) : ""
  qs   = req.params.sort.to_h.to_query
  sha  = Digest::SHA1.hexdigest("#{req.method}\n#{req.path}\n#{qs}\n#{body}")
  "contractkit:v1:#{api_name(req)}:#{req.path}:#{sha}"
end
```

### `:stale_if_error`

If the upstream returns 5xx and a cached value exists (even past TTL), return the cached value and log at `warn`. The cached value is annotated (`response.headers["X-Contractkit-Stale"] = "true"`) so consumers who care can branch. Useful for dashboards that prefer slightly-old data over nothing.

### What we explicitly don't do

- No write-behind cache. No background refresh. No "warm the cache" prefetch.
- No on-disk cache included. Bring your own (`ActiveSupport::Cache::FileStore` works fine).
- No cache invalidation API. TTLs only.

---

## 6. Logging

### Pluggable

Any object responding to `#debug`, `#info`, `#warn`, `#error` works. Default is a `Logger.new($stderr)` at `WARN` level so a quiet gem stays quiet.

```ruby
Contractkit.configure do |c|
  c.logger       = Rails.logger
  c.log_level    = :info        # symbol or Logger constant
  c.log_payloads = false        # default; never log response bodies in prod
end
```

### What gets logged

| Level | Event |
|---|---|
| `debug` | Every HTTP request (method, sanitized URL, duration); cache hit/miss; parser field-level oddities |
| `info` | Retry attempt; cache stale-fallback; rate-limiter sleep > 1s |
| `warn` | 429 received; data-quality oddity (unknown notice type, agency alias miss); silent cap on USASpending limit |
| `error` | Non-retryable upstream error; parse failure; rate limit exhausted |

### Format

Structured if the logger supports it (we check `logger.respond_to?(:tagged)` for ActiveSupport-style; otherwise plain). We do not depend on JSON-logging libraries.

```
[contractkit] [sam] GET /opportunities/v2/search status=200 duration_ms=412 retries=0
[contractkit] [usaspending] POST /api/v2/search/spending_by_award/ status=503 duration_ms=29000 retry=1/3
```

### Never logged

- `api_key` query param (redacted per §3).
- Full response bodies, unless `c.log_payloads = true` (off by default, explicitly opt-in for debugging).
- Request bodies on USASpending searches (the `filters` payload can contain user-derived data; treat as PII-adjacent).

> ⚠️ FILL IN: Confirm Vindor's logging convention — do downstream consumers prefer key=value (above) or structured JSON? Default to key=value unless there's a reason to bias the other way.

---

## 7. Timeouts

### Defaults

| Phase | Default | Rationale |
|---|---|---|
| Connect timeout | **5s** | A connect that takes 5s is a network problem, not a slow server |
| Read timeout (SAM) | **15s** | SAM responses are small (≤ 1MB); slow read = slow server |
| Read timeout (USASpending) | **30s** | Wide queries genuinely take 20+ seconds per [[usaspending]] §reliability-quirks |
| Total per attempt | derived | Connect + read |
| Total wall time including retries | unbounded by default | Caller's job to enforce via thread-level timeout if needed |

We deliberately do **not** enforce a wall-clock ceiling across retries. A caller that needs one wraps the call in `Timeout.timeout`. Reasons: retries with backoff can legitimately take 20-40s on a flaky network, and silently aborting partway through a retry sequence is worse than letting it finish.

### Per-call override

```ruby
client.opportunities.search(naics: "541512", timeout: 60)
```

The override flows into Faraday's request options for that one call. Connection-level timeouts (the default 5s connect) are not overridable per-call — they're a property of the connection pool.

### Configuration

```ruby
Contractkit.configure do |c|
  c.timeouts.connect              = 5
  c.timeouts.sam_read             = 15
  c.timeouts.usaspending_read     = 30
end
```

---

## Putting it together: the Faraday stack

The order matters. From outside (caller) to inside (network):

```ruby
# lib/contractkit/http/connection.rb
Faraday.new(url: base_url) do |f|
  f.request  :json                         # serialize POST bodies
  f.use      Contractkit::Http::LoggingMiddleware, logger: cfg.logger
  f.use      Contractkit::Http::RateLimiter,       bucket: bucket_for(api)
  f.use      Contractkit::Http::RetryMiddleware,   policy: cfg.retries
  f.use      Contractkit::Http::CacheMiddleware,   store: cfg.cache, ttl: cfg.cache_ttl if cfg.cache
  f.use      Contractkit::Http::ErrorMiddleware    # maps HTTP status → Contractkit::*Error
  f.response :json, content_type: /\bjson$/        # parse responses
  f.adapter  Faraday.default_adapter
end
```

Why this order:

- **Logging outermost** so we see the full retry timeline and post-cache latency.
- **Rate limiter before retry** so a retry consumes a fresh token (and gets paced if the bucket is empty).
- **Retry before cache** so a retried request can still populate the cache on success.
- **Cache before error** so cached responses bypass error mapping (they were already valid when stored).
- **Error mapping last in middleware** so it sees the raw response only after caching and retries are done.

---

## Cross-cutting: thread safety

| Component | Thread-safe? | Mechanism |
|---|---|---|
| `Contractkit::Configuration` | yes (read) | Frozen after `.configure` completes; mutable access guarded by `Monitor` per [[architecture-overview]] |
| `Contractkit::Client` | yes (read) | All state set at construction |
| `RateLimiter` | yes | `Mutex` inside `#acquire` |
| Cache | depends on store | We document the requirement; Rails.cache and `ActiveSupport::Cache::MemoryStore` are safe |
| Logger | depends on logger | Standard Ruby `Logger` is thread-safe |
| Faraday connection | yes | Faraday's adapter handles per-thread state |
| Lazy paginators | **no** | One iterator per thread; partition by date window for parallelism |

---

## What we explicitly did not build

- **A circuit breaker.** Faraday-retry's repeated-failure backoff is enough. A real circuit breaker (CLOSED/OPEN/HALF-OPEN) adds state and surprise; revisit if upstream outages become common.
- **Idempotency keys.** Both APIs are read-only. N/A.
- **A health check endpoint.** The caller can `Contractkit::Opportunity.search(limit: 1)` themselves.
- **Telemetry / metrics emission.** We log; consumers can scrape logs or wrap calls. No `prometheus-client` dependency.

---

## Open questions

> ⚠️ FILL IN: Does Vindor's production pipeline need cross-process rate limiting today? If yes, document the per-worker division pattern in the README and skip the Redis-extension question. If no, capture the threshold at which we'd reconsider.
>
> ⚠️ FILL IN: Confirm the SAM "key inactive" reaping window observed in practice — the docs say "inactive keys are reaped" but don't quantify. Inform the rotation guidance.
>
> ⚠️ FILL IN: Is `Total Outlays` (per [[usaspending]] §money-fields) a field we cache the same way as obligation, or does it move often enough to want a shorter TTL? Default to 1hr like the rest until we know.
