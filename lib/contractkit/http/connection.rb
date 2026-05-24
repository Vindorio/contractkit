# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require_relative "redactor"
require_relative "rate_limiter"

module Contractkit
  module Http
    # Builds the shared Faraday connection used by every HTTP-aware client
    # in the gem (SAM, USASpending, ...). One method, one stack: callers
    # don't get to assemble middleware out of order.
    #
    # Stack (request -> response), as ordered by Faraday's builder:
    #
    #   rate limiter   (#11 wires this; absent in v0.0.1)
    #   retry          (5xx + network errors only; jittered backoff)
    #   redactor       (api_key stripped from logged URLs)
    #   logger         (off unless config.logger is set)
    #   adapter        (net_http by default)
    #
    # Connect timeout 5s, read timeout = config.timeout (default 30s).
    # Both overridable per-call via the block argument to #build.
    module Connection
      # Status codes worth retrying. 5xx + the two Faraday network errors.
      # 4xx — including 429 — is never retried here; rate-limit handling
      # belongs in the rate-limiter middleware (#11), where backoff can
      # honor Retry-After deterministically rather than guessing.
      #
      # Faraday::RetriableResponse must be in the exceptions list because
      # faraday-retry implements retry_statuses by internally raising
      # RetriableResponse and re-catching it via the exceptions cascade.
      # Drop it and status-based retry silently stops working.
      RETRY_EXCEPTIONS = [
        Faraday::TimeoutError,
        Faraday::ConnectionFailed,
        Faraday::RetriableResponse
      ].freeze

      RETRY_STATUSES = [500, 502, 503, 504].freeze

      # @param config [Contractkit::Configuration] read-only at build time.
      # @yieldparam builder [Faraday::RackBuilder] for test-only adapter
      #   overrides (specs pass a Faraday::Adapter::Test stub).
      # @return [Faraday::Connection]
      def self.build(config)
        Faraday.new do |conn|
          conn.options.timeout      = config.timeout
          conn.options.open_timeout = 5

          # Rate limiter must run before retry — if we're already at the
          # upstream's per-minute cap, retry waiting won't help.
          conn.request :contractkit_rate_limiter

          conn.request :retry,
                       max: config.retries,
                       interval: 0.25,
                       interval_randomness: 0.5, # jitter ±50%
                       backoff_factor: 2, # 0.25 -> 0.5 -> 1.0
                       exceptions: RETRY_EXCEPTIONS,
                       retry_statuses: RETRY_STATUSES,
                       methods: %i[get post]

          if config.logger
            conn.response :logger, config.logger, { headers: false, bodies: false } do |log|
              Contractkit::Http::Redactor.apply!(log)
            end
          end

          conn.headers["User-Agent"] = config.user_agent

          yield conn if block_given?
        end
      end
    end
  end
end
