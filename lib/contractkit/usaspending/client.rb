# frozen_string_literal: true

require "json"
require_relative "../http/connection"

module Contractkit
  module Usaspending
    # Thin client over the USASpending.gov API. Returns raw parsed JSON
    # hashes — typed models (Contractkit::Award, Contractkit::Recipient)
    # layer on top in M2.
    #
    # USASpending is keyless. The only persistent concern is rate; the
    # rate limiter middleware handles that automatically per host.
    #
    # See docs/domain/usaspending.md for endpoint behavior and quirks.
    class Client
      # USASpending.gov v2 API base URL.
      BASE_URL = "https://api.usaspending.gov/api/v2"
      # Spending-by-award POST endpoint path.
      SEARCH_PATH = "/search/spending_by_award/"
      RECIPIENT_PATH = "/recipient/duns" # legacy "duns" path; the API moved to UEI but kept the URL

      # USASpending caps spending_by_award at 100 records per page. We
      # default to that — batch yields are one-page-per-batch and matching
      # upstream's natural page size keeps round-trip overhead minimal. See #32.
      DEFAULT_PAGE_SIZE = 100

      # Required fields list. USASpending's spending_by_award endpoint
      # returns 422 if `fields` is omitted. Verbatim from Vindor's
      # FetchAwardsJob::FIELDS per extraction-plan #2.
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

      # A/B/C/D are contract award types (definitive, purchase order,
      # delivery order, BPA call). Other letters are grants/loans/etc.;
      # the gem is contracts-focused so we default to these.
      CONTRACT_AWARD_TYPE_CODES = %w[A B C D].freeze

      def initialize(config: Contractkit.configuration)
        @config = config
        @connection = Contractkit::Http::Connection.build(config)
      end

      # POST /api/v2/search/spending_by_award/
      def raw_search(filters: {}, fields: DEFAULT_FIELDS, page: 1, limit: DEFAULT_PAGE_SIZE)
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
      def raw_recipient(uei)
        path = "#{RECIPIENT_PATH}/#{uei}/"
        response = @connection.get(BASE_URL + path)
        handle_response(response, path, :get, { uei: uei })
      end

      # Auto-paginated batch interface over spending_by_award.
      #
      # Yields one batch per API page (each batch is the raw `results`
      # array). Auto-fetches subsequent pages until page_metadata.hasNext
      # is false or the optional `limit:` cap is reached. Memory cost is
      # one page at a time.
      #
      # @example block form
      #   client.search(filters: {...}) do |batch|
      #     Award.upsert_batch(batch)
      #   end
      #
      # @example Enumerator form
      #   client.search(filters: {...}).each { |batch| ... }
      #
      # @param limit [Integer, nil] cap on total records across all pages.
      # @param per_page [Integer] page size; default is USASpending's max (100).
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def search(filters: {}, fields: DEFAULT_FIELDS, limit: nil, per_page: DEFAULT_PAGE_SIZE,
                 &block)
        unless block
          return enum_for(:search, filters: filters, fields: fields,
                                   limit: limit, per_page: per_page)
        end

        page = 1
        yielded = 0
        loop do
          response = raw_search(filters: filters, fields: fields, page: page, limit: per_page)
          batch = response["results"] || []
          break if batch.empty?

          batch = batch.first(limit - yielded) if limit && yielded + batch.size > limit

          yield batch
          yielded += batch.size

          break if limit && yielded >= limit
          break unless response.dig("page_metadata", "hasNext")

          page += 1
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

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
