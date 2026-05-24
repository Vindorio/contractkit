# frozen_string_literal: true

require "json"
require "date"
require_relative "../http/connection"

module Contractkit
  module Sam
    # Thin client over the SAM.gov Opportunities API. Returns raw parsed
    # JSON hashes — typed models (Contractkit::Opportunity) layer on top
    # via {Contractkit::Opportunity.search} in M2.
    #
    # Single endpoint surfaced for v0.1: GET /opportunities/v2/search.
    # See docs/domain/sam-gov.md for the field dictionary and quirks.
    class Client
      # SAM.gov Opportunities API search endpoint.
      BASE_URL = "https://api.sam.gov/opportunities/v2/search"

      # SAM's date format. Yes, MM/dd/yyyy. Yes, that's different from
      # USASpending's ISO 8601. Don't try to "normalize" — it's a stable
      # quirk of the upstream contract.
      DATE_FORMAT = "%m/%d/%Y"

      # Default notice-type filter: presolicitation + solicitation.
      DEFAULT_PTYPES = %w[p o].freeze

      # SAM's per-request cap. We default to it — batch yields are
      # one-page-per-batch and matching upstream's natural page size keeps
      # round-trip overhead minimal. See #32.
      DEFAULT_PAGE_SIZE = 1000

      def initialize(config: Contractkit.configuration)
        @config = config
        @connection = Contractkit::Http::Connection.build(config)
      end

      # GET /opportunities/v2/search with the given filters.
      #
      # @param params [Hash] SAM search params. Date values for postedFrom
      #   and postedTo accept Ruby Date; everything else is passed through.
      # @return [Hash] parsed JSON response with keys totalRecords, limit,
      #   offset, opportunitiesData, links.
      # @raise [Contractkit::ConfigurationError] when sam_api_key is missing
      # @raise [Contractkit::Sam::AuthenticationError] on 401/403/404
      # @raise [Contractkit::Sam::ServerError] on 5xx after retries
      # @raise [Contractkit::Sam::MalformedResponseError] on non-JSON body
      def raw_search(**params)
        ensure_api_key!

        normalized = normalize_params(params)
        response = @connection.get(BASE_URL, normalized)

        handle_response(response, normalized)
      end

      # Auto-paginated batch interface over /opportunities/v2/search.
      #
      # Yields one batch per API page (each batch is the raw
      # `opportunitiesData` array). Auto-fetches subsequent pages until
      # exhausted or the optional `limit:` cap is reached. Memory cost
      # is one page at a time — pages are not accumulated.
      #
      # @example block form (idiomatic for bulk pipelines)
      #   client.search(ncode: "541512") do |batch|
      #     Contract.upsert_batch(batch)
      #   end
      #
      # @example Enumerator form (chains lazily)
      #   client.search(ncode: "541512").each { |batch| ... }
      #   client.search(ncode: "541512").first.size  # => up to 1000
      #
      # @example record-level iteration via flat_map
      #   client.search(ncode: "541512").flat_map(&:itself).each { |opp| ... }
      #
      # @param limit [Integer, nil] cap on total records across all pages.
      #   Final batch is truncated to not exceed this.
      # @param per_page [Integer] page size; default is SAM's natural max (1000).
      # @return [Enumerator] when no block given.
      # @yieldparam batch [Array<Hash>] one API page of raw opportunity hashes.
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def search(limit: nil, per_page: DEFAULT_PAGE_SIZE, **params, &block)
        return enum_for(:search, limit: limit, per_page: per_page, **params) unless block

        offset = 0
        yielded = 0
        loop do
          page = raw_search(**params, limit: per_page, offset: offset)
          batch = page["opportunitiesData"] || []
          break if batch.empty?

          batch = batch.first(limit - yielded) if limit && yielded + batch.size > limit

          yield batch
          yielded += batch.size

          break if limit && yielded >= limit

          total = page["totalRecords"]
          break if total && offset + batch.size >= total

          offset += batch.size
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      def ensure_api_key!
        return unless @config.sam_api_key.nil? || @config.sam_api_key.to_s.empty?

        raise Contractkit::ConfigurationError,
              "SAM.gov API key not set. Configure via Contractkit.configure " \
              "{ |c| c.sam_api_key = ... } or set the SAM_API_KEY environment variable."
      end

      def normalize_params(params)
        normalized = params.transform_keys(&:to_sym)
        normalized[:api_key] = @config.sam_api_key

        %i[postedFrom postedTo].each do |key|
          value = normalized[key]
          normalized[key] = value.strftime(DATE_FORMAT) if value.is_a?(Date)
        end

        normalized[:ptype] ||= DEFAULT_PTYPES.join(",")

        normalized
      end

      def handle_response(response, params)
        loggable_params = params.except(:api_key)
        snippet = response.body.to_s[0, 256]

        case response.status
        when 200..299
          parse_json(response.body, loggable_params)
        when 401, 403
          raise auth_error(response.status, loggable_params, snippet)
        when 404
          # /opportunities/v2/search ALWAYS exists as an endpoint. A 404 here
          # in practice means the api.data.gov gateway silently rejected the
          # API key — empirically SAM returns 404 with empty body for bad
          # keys, not the documented 403 + API_KEY_INVALID JSON. Surface as
          # an auth error so callers can react meaningfully.
          raise auth_error(404, loggable_params, snippet)
        else
          raise Contractkit::Sam::ServerError.new(
            "SAM.gov returned HTTP #{response.status}",
            endpoint: BASE_URL, http_method: :get, params: loggable_params,
            status: response.status, response_snippet: snippet
          )
        end
      end

      def auth_error(status, params, snippet)
        Contractkit::Sam::AuthenticationError.new(
          "SAM.gov rejected API key (#{status})",
          endpoint: BASE_URL, http_method: :get, params: params,
          status: status, response_snippet: snippet
        )
      end

      def parse_json(body, loggable_params)
        JSON.parse(body)
      rescue JSON::ParserError => e
        raise Contractkit::Sam::MalformedResponseError.new(
          "SAM.gov returned non-JSON body: #{e.message}",
          endpoint: BASE_URL, http_method: :get, params: loggable_params,
          response_snippet: body.to_s[0, 256]
        )
      end
    end
  end
end
