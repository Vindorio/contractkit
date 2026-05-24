# frozen_string_literal: true

module Contractkit
  # Base for every error the gem raises. Carries the diagnostic fields a
  # caller needs to debug a failed call: endpoint, HTTP method, request
  # params, response status, and a snippet of the response body.
  #
  # Every API-shaped subclass inherits this contract. Per-API subclasses
  # under {Contractkit::Sam} and {Contractkit::Usaspending} let callers
  # rescue narrowly when they care which upstream failed; the cross-API
  # parents (RateLimitError etc.) let callers rescue by failure mode
  # regardless of source.
  class Error < StandardError
    attr_reader :endpoint, :http_method, :params, :status, :response_snippet

    def initialize(message = nil,
                   endpoint: nil,
                   http_method: nil,
                   params: nil,
                   status: nil,
                   response_snippet: nil)
      super(message)
      @endpoint         = endpoint
      @http_method      = http_method
      @params           = params
      @status           = status
      @response_snippet = response_snippet
    end
  end

  # 4xx — the upstream said the request was malformed or the resource is gone.
  class NotFoundError < Error; end

  # 401/403 — credentials are missing, expired, or unauthorized for the call.
  class AuthenticationError < Error; end

  # 5xx — upstream failure after retry exhaustion.
  class ServerError < Error; end

  # Response body could not be parsed as the expected shape.
  class MalformedResponseError < Error; end

  # Local config issue — missing key, malformed URL, conflicting options.
  # Raised before any HTTP call is made.
  class ConfigurationError < Error; end

  # 429 — upstream rate limit hit. `retry_after` reflects the upstream's
  # Retry-After header in seconds when present; nil when absent.
  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **)
      super(message, **)
      @retry_after = retry_after
    end
  end

  # Per-API namespacing. Each SAM-specific class inherits from its cross-API
  # parent so `rescue Contractkit::RateLimitError` catches SAM rate limits
  # alongside USASpending ones, while `rescue Contractkit::Sam::RateLimitError`
  # narrows to SAM only.
  #
  # Note: Ruby's single inheritance means a "rescue all SAM errors" base
  # class would conflict with the cross-API hierarchy. To catch any SAM
  # error in one rescue clause, use `rescue Contractkit::Error => e` and
  # check `e.endpoint` for the host.
  # SAM.gov-specific error variants. Each inherits from the cross-API
  # parent in {Contractkit} so callers can `rescue Contractkit::RateLimitError`
  # broadly or `rescue Contractkit::Sam::RateLimitError` narrowly.
  module Sam
    # SAM-specific 404 (resource not found).
    class NotFoundError          < Contractkit::NotFoundError; end
    # SAM-specific 401/403/404-from-bad-key.
    class AuthenticationError    < Contractkit::AuthenticationError; end
    # SAM-specific 5xx after retries exhausted.
    class ServerError            < Contractkit::ServerError; end
    # SAM-specific non-JSON or otherwise unparseable response body.
    class MalformedResponseError < Contractkit::MalformedResponseError; end
    # SAM-specific 429.
    class RateLimitError         < Contractkit::RateLimitError; end
  end

  # USASpending.gov-specific error variants. USASpending requires no
  # auth, so no AuthenticationError variant.
  module Usaspending
    # USASpending-specific 404.
    class NotFoundError          < Contractkit::NotFoundError; end
    # USASpending-specific 5xx after retries.
    class ServerError            < Contractkit::ServerError; end
    # USASpending-specific non-JSON response.
    class MalformedResponseError < Contractkit::MalformedResponseError; end
    # USASpending-specific 429.
    class RateLimitError         < Contractkit::RateLimitError; end
  end
end
