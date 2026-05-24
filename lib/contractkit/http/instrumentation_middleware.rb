# frozen_string_literal: true

require "faraday"
require_relative "../instrumentation"

module Contractkit
  module Http
    # Faraday middleware that emits request lifecycle events through
    # {Contractkit::Instrumentation}.
    #
    # Sits late in the stack — after rate-limiting, after retry — so the
    # events reflect the actual outbound attempt the consumer observes,
    # not the pre-retry "intent."
    class InstrumentationMiddleware < Faraday::Middleware
      # Faraday middleware entry point. Emits contractkit.request.start
      # before the call, contractkit.request.finish on success (with
      # status + duration), or contractkit.error on a raised exception.
      def call(env)
        start_payload = base_payload(env)
        Instrumentation.emit("contractkit.request.start", start_payload)

        started = monotonic
        response = @app.call(env)

        response.on_complete do |response_env|
          Instrumentation.emit(
            "contractkit.request.finish",
            start_payload.merge(
              status: response_env.status,
              duration_ms: ((monotonic - started) * 1000).round(2)
            )
          )
        end
      rescue StandardError => e
        Instrumentation.emit(
          "contractkit.error",
          start_payload.merge(
            error_class: e.class.name,
            error_message: e.message,
            duration_ms: ((monotonic - (started || monotonic)) * 1000).round(2)
          )
        )
        raise
      end

      private

      def base_payload(env)
        {
          url: env.url.to_s,
          method: env.method.to_s.upcase
        }
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

Faraday::Request.register_middleware(contractkit_instrumentation: Contractkit::Http::InstrumentationMiddleware)
