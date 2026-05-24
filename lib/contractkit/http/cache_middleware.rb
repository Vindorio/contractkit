# frozen_string_literal: true

require "digest"
require "faraday"

module Contractkit
  module Http
    # Opt-in response cache middleware. Off by default — wired in only
    # when `config.cache` is a non-nil object responding to
    # `#read(key)` / `#write(key, value, ttl:)`.
    #
    # Behavior:
    # - GET requests only. POSTs, PATCHes, etc. are passed through.
    # - 2xx responses only on write. 4xx/5xx are not cached.
    # - Cache key = SHA256(verb + url + sorted_query + body_hash).
    #   Sorting the query string makes `?a=1&b=2` and `?b=2&a=1` produce
    #   the same key, which matches what consumers actually mean.
    # - `config.cache = nil` (the default) short-circuits — the middleware
    #   passes through with zero overhead.
    #
    # The cache contract is intentionally minimal: ActiveSupport::Cache,
    # MemCacheStore, RedisCacheStore, a plain in-process Hash wrapper —
    # anything responding to read/write fits.
    class CacheMiddleware < Faraday::Middleware
      def initialize(app, config:)
        super(app)
        @config = config
      end

      # Faraday middleware entry point. Returns a Faraday::Response
      # synthesized from the cache on hit, otherwise calls the inner app
      # and writes the 2xx response to the cache.
      def call(env)
        return @app.call(env) unless cacheable_request?(env)

        # Compute the key BEFORE app.call — Faraday mutates env in flight
        # (env.body is nil for GET requests on entry, but on_complete sees
        # the RESPONSE body assigned into the same env). Computing once
        # upfront keeps read-key and write-key aligned.
        key = cache_key(env)

        cached = @config.cache.read(key)
        return rebuild_response(env, cached) if cached

        @app.call(env).on_complete do |response_env|
          write_cache(key, response_env) if response_env.status.between?(200, 299)
        end
      end

      private

      def cacheable_request?(env)
        @config.cache && env.method == :get
      end

      def cache_key(env)
        Digest::SHA256.hexdigest(
          [
            env.method.to_s.upcase,
            canonical_url(env.url),
            Digest::SHA256.hexdigest(env.body.to_s)
          ].join("\0")
        )
      end

      def canonical_url(uri)
        sorted_query = (uri.query || "").split("&").sort.join("&")
        port = uri.port && uri.default_port != uri.port ? ":#{uri.port}" : ""
        "#{uri.scheme}://#{uri.host}#{port}#{uri.path}?#{sorted_query}"
      end

      def write_cache(key, response_env)
        @config.cache.write(
          key,
          {
            status: response_env.status,
            headers: response_env.response_headers.to_h,
            body: response_env.body
          },
          ttl: @config.cache_ttl
        )
      end

      def rebuild_response(env, cached)
        env.status           = cached[:status]
        env.response_headers = Faraday::Utils::Headers.new(cached[:headers] || {})
        env.body             = cached[:body]
        Faraday::Response.new(env)
      end
    end
  end
end

Faraday::Request.register_middleware(contractkit_cache: Contractkit::Http::CacheMiddleware)
