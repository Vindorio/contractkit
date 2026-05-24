# frozen_string_literal: true

module Contractkit
  # HTTP transport layer: Faraday connection builder, rate-limiter,
  # cache, instrumentation, and redaction middleware. Internal —
  # consumers normally don't interact with these directly.
  module Http
    # Single source of truth for "what counts as a secret in our logs."
    #
    # Today this only redacts the SAM.gov `api_key=` query parameter, which
    # is the only secret the gem puts on the wire (USASpending is keyless).
    # If we ever add bodies/headers carrying secrets, extend Redactor first
    # and re-wire the logger filter — never sprinkle redaction at call sites.
    module Redactor
      # Matches SAM.gov api_key query params; capture group 1 preserves
      # the `api_key=` prefix so {REPLACEMENT} keeps the param name in
      # the log line.
      SAM_API_KEY_PATTERN = /(api_key=)([^&\s"]+)/
      # The replacement string fed to gsub — keeps the param key,
      # masks the value.
      REPLACEMENT = '\1[REDACTED]'

      # Wires the redaction filter into a Faraday::Logger middleware.
      # @param logger [Faraday::Response::Logger]
      def self.apply!(logger)
        logger.filter(SAM_API_KEY_PATTERN, REPLACEMENT)
      end

      # Standalone scrubber, useful for tests and ad-hoc string scrubbing
      # outside Faraday's logger pipeline.
      def self.scrub(text)
        text.to_s.gsub(SAM_API_KEY_PATTERN, REPLACEMENT)
      end
    end
  end
end
