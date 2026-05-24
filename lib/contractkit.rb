# frozen_string_literal: true

require_relative "contractkit/version"
require_relative "contractkit/error"
require_relative "contractkit/configuration"
require_relative "contractkit/client"
require_relative "contractkit/instrumentation"
require_relative "contractkit/http/redactor"
require_relative "contractkit/http/rate_limiter"
require_relative "contractkit/http/instrumentation_middleware"
require_relative "contractkit/http/cache_middleware"
require_relative "contractkit/http/connection"
require_relative "contractkit/sam/client"
require_relative "contractkit/usaspending/client"
require_relative "contractkit/agency"
require_relative "contractkit/naics"
require_relative "contractkit/set_aside"
require_relative "contractkit/psc"
require_relative "contractkit/place_of_performance"
require_relative "contractkit/opportunity"
require_relative "contractkit/opportunity_search"
require_relative "contractkit/sam/response_parser"
require_relative "contractkit/recipient"
require_relative "contractkit/period"
require_relative "contractkit/award"
require_relative "contractkit/award_search"
require_relative "contractkit/usaspending/response_parser"

# Top-level namespace for contractkit. See README.md and docs/ for usage.
module Contractkit
  class << self
    # The global Configuration singleton. Lazily instantiated; reading
    # without ever calling .configure gives you the defaults.
    def configuration
      @configuration ||= Configuration.new
    end

    # Yields the global Configuration for batch mutation.
    #
    # @example
    #   Contractkit.configure do |c|
    #     c.sam_api_key = ENV["SAM_API_KEY"]
    #     c.timeout     = 60
    #   end
    def configure
      yield configuration
      configuration
    end

    # Reset the global configuration to defaults. Primarily for tests;
    # production code should not call this.
    def reset_configuration!
      @configuration = nil
    end
  end
end
