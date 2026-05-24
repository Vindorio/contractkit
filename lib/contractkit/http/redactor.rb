# frozen_string_literal: true

module Contractkit
  module Http
    # Single source of truth for "what counts as a secret in our logs."
    #
    # Today this only redacts the SAM.gov `api_key=` query parameter, which
    # is the only secret the gem puts on the wire (USASpending is keyless).
    # If we ever add bodies/headers carrying secrets, extend Redactor first
    # and re-wire the logger filter — never sprinkle redaction at call sites.
    module Redactor
      SAM_API_KEY_PATTERN = /(api_key=)([^&\s"]+)/
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
