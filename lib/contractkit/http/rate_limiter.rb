# frozen_string_literal: true

require "faraday"
require "monitor"
require_relative "../instrumentation"

module Contractkit
  module Http
    # Per-host token-bucket rate limiter for outbound Faraday requests.
    #
    # Why per-host: SAM.gov is documented at much tighter limits than
    # USASpending.gov (~20 req/min sustained vs ~5 req/sec). One global
    # bucket would either throttle USASpending unnecessarily or get us
    # 429s from SAM. The bucket is keyed on `env.url.host` so each
    # upstream gets its own budget independent of the other.
    #
    # Behavior:
    # - Empty bucket on request: block until a token refills. Never raises.
    # - Upstream 429 response: drain the bucket so the next attempt waits
    #   for `Retry-After` seconds, then re-raise as a
    #   {Contractkit::RateLimitError} (per-API subclass when host is known).
    #
    # Defaults are deliberately conservative — see DEFAULTS below. Override
    # via `configure_host` at boot if you need looser pacing.
    class RateLimiter < Faraday::Middleware
      # Single token bucket. Refills continuously at `rate` tokens per
      # second up to `capacity`. Thread-safe under a Monitor.
      class Bucket
        attr_reader :capacity, :rate

        def initialize(capacity:, rate:, clock: nil)
          @capacity   = capacity.to_f
          @rate       = rate.to_f
          @tokens     = @capacity
          @last       = (clock || method(:monotonic)).call
          @clock      = clock || method(:monotonic)
          @monitor    = Monitor.new
        end

        # Take one token, blocking until one is available.
        # @return [Float] seconds slept (0 if a token was immediately available).
        def take
          wait = 0.0
          @monitor.synchronize do
            refill!
            if @tokens < 1
              wait = (1 - @tokens) / @rate
              sleep_for(wait)
              refill!
            end
            @tokens -= 1
          end
          wait
        end

        # Drain the bucket so the next take blocks for at least `seconds`.
        # Used after a 429 response to respect upstream's Retry-After window.
        def drain(seconds)
          @monitor.synchronize do
            @tokens = -(seconds.to_f * @rate)
            @last   = @clock.call
          end
        end

        # Snapshot of current bucket fill (for instrumentation / specs).
        def tokens
          @monitor.synchronize do
            refill!
            @tokens
          end
        end

        private

        def refill!
          now     = @clock.call
          elapsed = now - @last
          @tokens = [@tokens + (elapsed * @rate), @capacity].min
          @last   = now
        end

        def sleep_for(seconds)
          sleep(seconds) if seconds.positive?
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      # Host → bucket config. Capacity and rate (tokens per second).
      DEFAULTS = {
        "api.sam.gov" => { capacity: 20, rate: 20.0 / 60 }, # ~20/min sustained
        "api.usaspending.gov" => { capacity: 5, rate: 5.0 } # ~5/sec sustained
      }.freeze

      # @param app [Faraday Middleware]
      # @param host_rates [Hash{String=>Hash}] override map merged on top of DEFAULTS
      def initialize(app, host_rates: {})
        super(app)
        @rates    = DEFAULTS.merge(host_rates)
        @buckets  = {}
        @monitor  = Monitor.new
      end

      # Faraday middleware entry point. Blocks (sleeps) when the
      # per-host bucket is empty; raises {Contractkit::RateLimitError}
      # variants when the upstream returns 429 (after draining the
      # bucket by Retry-After).
      def call(env)
        wait = bucket_for(env.url.host)&.take
        if wait&.positive?
          Instrumentation.emit(
            "contractkit.rate_limit_wait",
            host: env.url.host,
            wait_seconds: wait.round(3)
          )
        end

        @app.call(env).on_complete do |response_env|
          handle_429(response_env, env.url.host) if response_env.status == 429
        end
      end

      private

      def bucket_for(host)
        config = @rates[host]
        return nil unless config

        @monitor.synchronize do
          @buckets[host] ||= Bucket.new(**config)
        end
      end

      # rubocop:disable Naming/VariableNumber -- 429 is a documented HTTP status, not a magic number
      def handle_429(response_env, host)
        retry_after = parse_retry_after(response_env.response_headers["Retry-After"])
        bucket_for(host)&.drain(retry_after) if retry_after.positive?

        raise rate_limit_error_for(host).new(
          "upstream rate limit hit (429)",
          retry_after: retry_after.positive? ? retry_after : nil,
          endpoint: response_env.url.to_s,
          http_method: response_env.method.to_s.upcase.to_sym,
          status: 429,
          response_snippet: response_env.body.to_s[0, 256]
        )
      end
      # rubocop:enable Naming/VariableNumber

      def parse_retry_after(value)
        return 0.0 if value.nil? || value.to_s.empty?

        Float(value)
      rescue ArgumentError
        # Retry-After can be an HTTP-date. Parsing that for v0.1 is out
        # of scope — treat as "wait the default poll interval" by
        # returning 0, letting the next take() block naturally.
        0.0
      end

      def rate_limit_error_for(host)
        case host
        when /sam\.gov\z/         then Contractkit::Sam::RateLimitError
        when /usaspending\.gov\z/ then Contractkit::Usaspending::RateLimitError
        else                           Contractkit::RateLimitError
        end
      end
    end
  end
end

Faraday::Request.register_middleware(contractkit_rate_limiter: Contractkit::Http::RateLimiter)
