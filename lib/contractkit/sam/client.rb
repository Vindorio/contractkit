# frozen_string_literal: true

require "json"
require "date"
require_relative "../http/connection"

module Contractkit
  module Sam
    # Thin client over the SAM.gov Opportunities API. Returns raw parsed
    # JSON hashes — typed models (Contractkit::Opportunity) arrive in M2.
    #
    # Single endpoint surfaced for v0.1: GET /opportunities/v2/search.
    # All filter / paging concerns are passed through as query params.
    # See docs/domain/sam-gov.md for the field dictionary and known
    # behaviors.
    class Client
      BASE_URL = "https://api.sam.gov/opportunities/v2/search"

      # SAM's date format. Yes, MM/dd/yyyy. Yes, that's different from
      # USASpending's ISO 8601. Don't try to "normalize" — it's a stable
      # quirk of the upstream contract.
      DATE_FORMAT = "%m/%d/%Y"

      # Default notice-type filter when caller doesn't specify one:
      # presolicitation + solicitation. Matches what Vindor pulls.
      DEFAULT_PTYPES = %w[p o].freeze

      def initialize(config: Contractkit.configuration)
        @config = config
        @connection = Contractkit::Http::Connection.build(config)
      end

      # GET /opportunities/v2/search with the given filters.
      #
      # @param params [Hash] SAM search params. Date values for postedFrom
      #   and postedTo accept Ruby Date; everything else is passed through
      #   verbatim.
      # @return [Hash] parsed JSON response with keys totalRecords, limit,
      #   offset, opportunitiesData, links.
      # @raise [Contractkit::ConfigurationError] when sam_api_key is missing
      # @raise [Contractkit::Sam::AuthenticationError] on 401/403
      # @raise [Contractkit::Sam::ServerError] on 5xx after retries
      # @raise [Contractkit::Sam::MalformedResponseError] on non-JSON body
      def raw_search(**params)
        ensure_api_key!

        normalized = normalize_params(params)
        response = @connection.get(BASE_URL, normalized)

        handle_response(response, normalized)
      end

      # Returns a lazy Enumerable over every opportunity matching the
      # filters, transparently paginating via offset/limit.
      #
      # @example
      #   client.search(naics: "541512", per_page: 200).take(50)
      def search(per_page: 100, **params)
        Pagination::Offset.new(client: self, params: params, per_page: per_page)
      end

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
          # an auth error so callers can react meaningfully. When future
          # endpoints (e.g. /opportunities/v2/{noticeId}) need real 404
          # semantics, route them through a separate handler.
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
