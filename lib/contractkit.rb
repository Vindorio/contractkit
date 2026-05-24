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
require_relative "contractkit/sam/pagination"
require_relative "contractkit/sam/client"
require_relative "contractkit/usaspending/pagination"
require_relative "contractkit/usaspending/client"

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
