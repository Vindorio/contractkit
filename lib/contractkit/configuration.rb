# frozen_string_literal: true

require "logger"
require "monitor"

module Contractkit
  # Mutable, thread-safe configuration object. The gem ships one global
  # instance reachable via {Contractkit.configure}; consumers needing
  # isolation (multi-tenant SaaS) instead pass options to
  # {Contractkit::Client.new}.
  #
  # All reads and writes are guarded by an internal {Monitor} so concurrent
  # threads see consistent state. Callers should treat the configuration
  # as effectively read-only after their setup phase finishes — flipping
  # it under traffic works but is rarely what you want.
  class Configuration
    DEFAULTS = {
      sam_api_key: nil,
      user_agent: "contractkit/#{Contractkit::VERSION} (+https://github.com/gudetimes1234/contractkit)",
      timeout: 30,
      retries: 3,
      logger: nil,
      cache: nil,
      cache_ttl: 0
    }.freeze

    OPTIONS = DEFAULTS.keys.freeze

    attr_writer(*OPTIONS)

    # @param overrides [Hash] keyword overrides for any of the DEFAULTS keys.
    #   Unknown keys raise ConfigurationError to catch typos early.
    def initialize(**overrides)
      @monitor = Monitor.new

      DEFAULTS.each { |k, v| instance_variable_set("@#{k}", v) }
      # Pick up the conventional env var on construction (consumers may
      # still override via the block).
      @sam_api_key = ENV.fetch("SAM_API_KEY", @sam_api_key)

      overrides.each do |key, value|
        unless OPTIONS.include?(key)
          raise ConfigurationError, "unknown configuration option: #{key.inspect}"
        end

        instance_variable_set("@#{key}", value)
      end
    end

    OPTIONS.each do |opt|
      define_method(opt) { @monitor.synchronize { instance_variable_get("@#{opt}") } }
    end

    # Registers (or returns) the event-emission callback. With a block,
    # the block becomes the registered callback. Without one, returns
    # the currently-registered callback (or nil).
    #
    # @example
    #   Contractkit.configure do |c|
    #     c.on_event { |name, payload| MyApp::Telemetry.track(name, payload) }
    #   end
    def on_event(&block)
      @monitor.synchronize do
        @on_event = block if block
        @on_event
      end
    end

    # Yields self in a synchronized block so consumers can mutate multiple
    # fields atomically.
    def update
      @monitor.synchronize { yield self }
      self
    end

    # Snapshot of every option, for instrumentation / debug.
    def to_h
      @monitor.synchronize { OPTIONS.to_h { |k| [k, instance_variable_get("@#{k}")] } }
    end

    # Build a derivative configuration overriding only the named keys.
    # Used by Client to layer per-call overrides without touching the
    # caller's instance.
    def merge(**overrides)
      self.class.new(**to_h, **overrides)
    end
  end
end
