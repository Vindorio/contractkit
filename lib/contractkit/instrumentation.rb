# frozen_string_literal: true

module Contractkit
  # Cross-cutting event emission. Two paths, both optional, both
  # framework-agnostic by default:
  #
  # 1. **Block hook.** Consumers register one callable via
  #    `Contractkit.configure { |c| c.on_event { |name, payload| ... } }`.
  #    Every emitted event flows through it.
  #
  # 2. **ActiveSupport::Notifications.** If AS is loaded (via Rails, or
  #    explicitly required by the consumer), the same events publish
  #    through `ActiveSupport::Notifications.instrument` so AS subscribers
  #    pick them up alongside the block hook. AS is **not** a dependency
  #    of the gem; emission falls back to a no-op when it's absent.
  #
  # Event names follow the convention `contractkit.<area>` (see EVENTS
  # below). Payloads are plain Hashes with String|Symbol keys.
  module Instrumentation
    EVENTS = %w[
      contractkit.request.start
      contractkit.request.finish
      contractkit.retry
      contractkit.rate_limit_wait
      contractkit.error
    ].freeze

    # @param name [String] one of EVENTS (not strictly enforced — keep open
    #   for future events without a schema bump).
    # @param payload [Hash, nil] event payload (positional hash form).
    # @param config [Contractkit::Configuration] the configuration whose
    #   `on_event` block (if any) should fire. Defaults to the global
    #   singleton; Client-scoped emission passes its own config.
    # @param kwargs [Hash] alternative payload form for shorthand call sites
    #   that prefer keyword args (`emit("...", url: "x")`). Merged on top
    #   of the positional payload if both are given.
    def self.emit(name, payload = nil, config: Contractkit.configuration, **kwargs)
      effective = (payload || {}).merge(kwargs)
      config.on_event&.call(name, effective)
      activesupport_emit(name, effective)
    end

    # AS bridge. Wrapped so unit tests can stub it without monkey-patching
    # AS::Notifications and so the no-op path is explicit.
    def self.activesupport_emit(name, payload)
      return unless defined?(ActiveSupport::Notifications)

      ActiveSupport::Notifications.instrument(name, payload)
    end
  end
end
