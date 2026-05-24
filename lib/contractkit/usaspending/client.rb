# frozen_string_literal: true

require "json"
require_relative "../http/connection"

module Contractkit
  module Usaspending
    # Thin client over the USASpending.gov API. Returns raw parsed JSON
    # hashes — typed models (Contractkit::Award, Contractkit::Recipient)
    # arrive in M2.
    #
    # USASpending is keyless. The only persistent concern is the rate at
    # which we hit it; the rate limiter middleware (set per-host in
    # Contractkit::Http::RateLimiter::DEFAULTS) handles that automatically.
    #
    # See docs/domain/usaspending.md for endpoint behavior, money-field
    # semantics, and known quirks (POST-with-filters shape, page-based
    # pagination, timeouts on wide queries).
    class Client
      BASE_URL = "https://api.usaspending.gov/api/v2"
      SEARCH_PATH = "/search/spending_by_award/"
      RECIPIENT_PATH = "/recipient/duns" # canonical despite the legacy "duns" path

      # Default fields requested on spending_by_award. The endpoint REQUIRES
      # a fields array; omitting it returns 422. This set is a workable
      # baseline; callers override per request.
      #
      # Verbatim from Vindor's FetchAwardsJob::FIELDS list per
      # extraction-plan #2 (the field names are the human-readable strings
      # USASpending's response uses as keys — yes, they include spaces).
      DEFAULT_FIELDS = [
        "Award ID",
        "Recipient Name",
        "Recipient UEI",
        "Award Amount",
        "Total Outlays",
        "Description",
        "Contract Award Type",
        "Awarding Agency",
        "Awarding Sub Agency",
        "Awarding Office",
        "Funding Agency",
        "Funding Sub Agency",
        "Start Date",
        "End Date",
        "NAICS",
        "PSC",
        "Place of Performance State Code",
        "Place of Performance Country Code",
        "Place of Performance Zip5",
        "recipient_id"
      ].freeze

      # USASpending's award-type taxonomy. A/B/C/D are contracts (definitive,
      # purchase order, delivery order, BPA call). Other letters are
      # grants/loans/etc.; the gem is contracts-focused so we default to
      # %w[A B C D].
      CONTRACT_AWARD_TYPE_CODES = %w[A B C D].freeze

      def initialize(config: Contractkit.configuration)
        @config = config
        @connection = Contractkit::Http::Connection.build(config)
      end

      # POST /api/v2/search/spending_by_award/
      #
      # @param filters [Hash] passed through verbatim. award_type_codes
      #   defaults to contracts (A/B/C/D) if the caller doesn't supply it.
      # @param fields [Array<String>] response fields; defaults to
      #   DEFAULT_FIELDS.
      # @param page [Integer] 1-indexed.
      # @param limit [Integer] page size; USASpending caps at 100.
      # @return [Hash] parsed JSON with keys `results` and `page_metadata`.
      def raw_search(filters: {}, fields: DEFAULT_FIELDS, page: 1, limit: 100)
        body = {
          filters: with_default_award_types(filters),
          fields: fields,
          page: page,
          limit: limit
        }

        response = @connection.post(BASE_URL + SEARCH_PATH) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = JSON.generate(body)
        end

        handle_response(response, SEARCH_PATH, :post, body)
      end

      # GET /api/v2/recipient/duns/{uei}/
      #
      # The "duns" path segment is legacy — the API moved to UEI in 2022 but
      # kept the URL stable.
      def raw_recipient(uei)
        path = "#{RECIPIENT_PATH}/#{uei}/"
        response = @connection.get(BASE_URL + path)
        handle_response(response, path, :get, { uei: uei })
      end

      # Returns a lazy Enumerable over every award matching the filters,
      # transparently paginating until page_metadata.hasNext is false.
      def search(filters: {}, fields: DEFAULT_FIELDS, limit: 100)
        Pagination::Page.new(
          client: self,
          filters: filters,
          fields: fields,
          limit: limit
        )
      end

      private

      def with_default_award_types(filters)
        filters = filters.transform_keys(&:to_s)
        filters["award_type_codes"] ||= CONTRACT_AWARD_TYPE_CODES.dup
        filters
      end

      def handle_response(response, path, method, request_payload)
        snippet = response.body.to_s[0, 256]

        case response.status
        when 200..299
          parse_json(response.body, path, method, request_payload)
        when 404
          raise Contractkit::Usaspending::NotFoundError.new(
            "USASpending returned 404",
            endpoint: BASE_URL + path, http_method: method, params: request_payload,
            status: 404, response_snippet: snippet
          )
        else
          raise Contractkit::Usaspending::ServerError.new(
            "USASpending returned HTTP #{response.status}",
            endpoint: BASE_URL + path, http_method: method, params: request_payload,
            status: response.status, response_snippet: snippet
          )
        end
      end

      def parse_json(body, path, method, request_payload)
        JSON.parse(body)
      rescue JSON::ParserError => e
        raise Contractkit::Usaspending::MalformedResponseError.new(
          "USASpending returned non-JSON body: #{e.message}",
          endpoint: BASE_URL + path, http_method: method, params: request_payload,
          response_snippet: body.to_s[0, 256]
        )
      end
    end
  end
end
