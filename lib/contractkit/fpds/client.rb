# frozen_string_literal: true

require "json"
require_relative "../http/connection"

module Contractkit
  module Fpds
    # Thin client over the SAM.gov Contract Awards API (the canonical
    # successor to the decommissioned FPDS ATOM feed). Returns raw
    # parsed JSON hashes — typed models layer on top via
    # {Contractkit::Fpds::ResponseParser}.
    #
    # Auth is via the SAM.gov API key (config.sam_api_key). The
    # Contract Awards API uses GET with query parameters.
    #
    # Note: 429 (rate limit) errors from this client raise
    # {Contractkit::Sam::RateLimitError} because the host `api.sam.gov`
    # is shared with the SAM.gov client and the rate-limiter middleware
    # handles 429s before they reach client-level error handling.
    #
    # API docs: https://open.gsa.gov/api/contract-awards/
    # Endpoint: https://api.sam.gov/contract-awards/v1/search
    class Client
      # SAM.gov Contract Awards v1 API base URL.
      BASE_URL = "https://api.sam.gov/contract-awards/v1"
      SEARCH_PATH = "/search"

      # Default page size (10 per SAM.gov default).
      DEFAULT_PAGE_SIZE = 10
      # Max page size (100 per SAM.gov docs).
      MAX_PAGE_SIZE = 100

      # Snake_case → camelCase parameter mapping for the SAM.gov
      # Contract Awards API. All parameters in the API are camelCase.
      PARAM_MAP = {
        "contracting_department_code" => "contractingDepartmentCode",
        "contracting_subtier_code" => "contractingSubtierCode",
        "contracting_subtier_name" => "contractingSubtierName",
        "contracting_office_code" => "contractingOfficeCode",
        "funding_department_code" => "fundingDepartmentCode",
        "funding_subtier_code" => "fundingSubtierCode",
        "funding_subtier_name" => "fundingSubtierName",
        "funding_office_code" => "fundingOfficeCode",
        "naics_code" => "naicsCode",
        "product_or_service_code" => "productOrServiceCode",
        "last_modified_date" => "lastModifiedDate",
        "approved_date" => "approvedDate",
        "date_signed" => "dateSigned",
        "created_date" => "createdDate",
        "closed_date" => "closedDate",
        "fiscal_year" => "fiscalYear",
        "dollars_obligated" => "dollarsObligated",
        "total_dollars_obligated" => "totalDollarsObligated",
        "modification_number" => "modificationNumber",
        "award_or_idv" => "awardOrIDV",
        "award_or_idv_type_code" => "awardOrIDVTypeCode",
        "include_sections" => "includeSections",
        "period_of_performance_start_date" => "periodOfPerformanceStartDate",
        "current_completion_date" => "currentCompletionDate",
        "ultimate_completion_date" => "ultimateCompletionDate",
        "awardee_unique_entity_id" => "awardeeUniqueEntityId",
        "awardee_cage_code" => "awardeeCageCode",
        "place_of_perform_state_code" => "placeOfPerformStateCode",
        "place_of_perform_zip_code" => "placeOfPerformZipCode",
        "solicitation_date" => "solicitationDate",
        "ultimate_contract_value" => "ultimateContractValue",
        "total_ultimate_contract_value" => "totalUltimateContractValue",
        "non_government_dollars" => "nonGovernmentDollars",
        "total_non_government_dollars" => "totalNonGovernmentDollars"
      }.freeze

      def initialize(config: Contractkit.configuration)
        @config = config
        @connection = Contractkit::Http::Connection.build(config)
      end

      # GET /contract-awards/v1/search
      #
      # Query parameters map to SAM.gov documented params. Both camelCase
      # and snake_case keys are accepted (snake_case is converted internally).
      # Date params accept ISO8601 strings or Date objects and are formatted
      # as MM/DD/YYYY for SAM.gov. Ranges use bracket notation:
      #   [MM/DD/YYYY,MM/DD/YYYY]
      #
      # @param filters [Hash] search parameters. Supported keys:
      #   :contracting_department_code, :contracting_subtier_code,
      #   :funding_department_code, :funding_subtier_code,
      #   :naics_code, :product_or_service_code,
      #   :last_modified_date, :approved_date, :date_signed,
      #   :dollars_obligated, :modification_number,
      #   :award_or_idv, :limit, :offset,
      #   :include_sections, :q, and any other SAM.gov param
      #   (camelCase variants also accepted directly).
      # @return [Hash] raw parsed JSON response
      def raw_search(filters = {})
        params = build_query_params(filters)

        response = @connection.get(BASE_URL + SEARCH_PATH, params)
        handle_response(response, SEARCH_PATH, :get, params)
      end

      # Auto-paginated batch interface. Yields one batch per API page
      # (the raw `awardSummary` array). Auto-fetches until totalRecords
      # is exhausted or the optional `limit:` cap is reached.
      #
      # @example block form
      #   client.search(contracting_department_code: "9700") do |batch|
      #     batch.each { |award| process(award) }
      #   end
      #
      # @example Enumerator form
      #   client.search(naics_code: "541512").each { |batch| ... }
      #
      # @param filters [Hash] search parameters (see #raw_search)
      # @param limit [Integer, nil] cap on total records across all pages
      # @param per_page [Integer] page size (max 100)
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def search(filters = {}, limit: nil, per_page: DEFAULT_PAGE_SIZE, &block)
        unless block
          return enum_for(:search, filters, limit: limit, per_page: per_page)
        end

        page_size = [per_page, MAX_PAGE_SIZE].min
        offset = 0
        yielded = 0

        loop do
          page_filters = filters.merge(limit: page_size, offset: offset)
          response = raw_search(page_filters)
          batch = response["awardSummary"] || []
          break if batch.empty?

          batch = batch.first(limit - yielded) if limit && yielded + batch.size > limit

          yield batch
          yielded += batch.size

          break if limit && yielded >= limit
          break if offset + batch.size >= response["totalRecords"].to_i

          offset += page_size
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      def build_query_params(filters)
        params = {}
        params["api_key"] = @config.sam_api_key

        filters.each do |key, value|
          param_name = normalize_param_name(key.to_s)
          param_value = format_param_value(param_name, value)
          params[param_name] = param_value unless param_value.nil?
        end

        params
      end

      # Convert snake_case keys to camelCase per the SAM.gov API spec.
      # Keys already in camelCase (or other non-snake forms) pass through.
      def normalize_param_name(name)
        # Direct match in the map
        return PARAM_MAP[name] if PARAM_MAP.key?(name)

        # Already camelCase or unknown — pass through
        name
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      def format_param_value(name, value)
        case name
        when "lastModifiedDate", "approvedDate", "dateSigned",
             "createdDate", "closedDate", "periodOfPerformanceStartDate",
             "currentCompletionDate", "ultimateCompletionDate",
             "solicitationDate"
          format_date_range(value)
        when "dollarsObligated", "totalDollarsObligated",
             "ultimateContractValue", "totalUltimateContractValue",
             "nonGovernmentDollars", "totalNonGovernmentDollars"
          format_dollar_range(value)
        when "includeSections"
          value.is_a?(Array) ? value.join(",") : value.to_s
        when "modificationNumber", "limit", "offset"
          value.to_s
        else
          value.to_s
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity

      # SAM.gov date ranges: "MM/DD/YYYY" or "[MM/DD/YYYY,MM/DD/YYYY]"
      def format_date_range(value)
        return format_date(value) unless value.is_a?(Array)

        start_str = format_date(value[0])
        end_str = format_date(value[1])
        return nil unless start_str || end_str

        start_str ||= ""
        end_str ||= ""
        "[#{start_str},#{end_str}]"
      end

      def format_date(value)
        return nil if value.nil? || value.to_s.strip.empty?

        d = value.respond_to?(:strftime) ? value : Date.parse(value.to_s)
        d.strftime("%m/%d/%Y")
      rescue ArgumentError, TypeError
        nil
      end

      # Dollar ranges: "[0.0,100000000.99]" or single value "50000.00"
      def format_dollar_range(value)
        return value.to_s unless value.is_a?(Array)

        "[#{value[0]},#{value[1]}]"
      end

      def handle_response(response, path, method, request_params)
        snippet = response.body.to_s[0, 256]

        case response.status
        when 200..299
          parse_json(response.body, path, method, request_params)
        when 401, 403
          raise Contractkit::Fpds::AuthenticationError.new(
            "SAM.gov Contract Awards API returned HTTP #{response.status}",
            endpoint: BASE_URL + path, http_method: method, params: request_params,
            status: response.status, response_snippet: snippet
          )
        when 404
          raise Contractkit::Fpds::NotFoundError.new(
            "SAM.gov Contract Awards API returned 404",
            endpoint: BASE_URL + path, http_method: method, params: request_params,
            status: 404, response_snippet: snippet
          )
        else
          raise Contractkit::Fpds::ServerError.new(
            "SAM.gov Contract Awards API returned HTTP #{response.status}",
            endpoint: BASE_URL + path, http_method: method, params: request_params,
            status: response.status, response_snippet: snippet
          )
        end
      end

      def parse_json(body, path, method, request_params)
        JSON.parse(body)
      rescue JSON::ParserError => e
        raise Contractkit::Fpds::MalformedResponseError.new(
          "SAM.gov Contract Awards API returned non-JSON body: #{e.message}",
          endpoint: BASE_URL + path, http_method: method, params: request_params,
          response_snippet: body.to_s[0, 256]
        )
      end
    end
  end
end
