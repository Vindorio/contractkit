# frozen_string_literal: true

require "date"
require "json"
require_relative "../http/connection"

module Contractkit
  module Sam
    # SAM.gov Entity Management API client + parser.
    #
    # Endpoint: GET https://api.sam.gov/entity-information/v3/entities
    # Auth: same `api_key` query param as Opportunities (reuses the
    # configured `sam_api_key`).
    #
    # Decision (per issue #39): exclusion status is folded into the
    # entity response when the entity API includes the `exclusionStatusFlag`
    # field. A separate Exclusions client is **deferred** — when the
    # Tango research and SAM dashboards show exclusions surfaced inline
    # on the Entity record, we lean on that. A dedicated Exclusions
    # client (`Contractkit::Sam::Exclusions`) is filed as a follow-up
    # for when historic / multi-record exclusion lookup is needed.
    # See docs/domain/entities.md for the trade-off.
    module Entities
      BASE_URL = "https://api.sam.gov/entity-information/v3/entities"

      # Fetch one entity by UEI. Returns a fully-populated
      # {Contractkit::Recipient}.
      #
      # @param uei [String] 12-char SAM UEI
      # @param client [Contractkit::Sam::Entities::Client, nil]
      # @return [Contractkit::Recipient]
      # @raise [Contractkit::NotFoundError] when SAM has no record for the UEI
      def self.find(uei, client: nil)
        c = client || Client.new
        raw = c.raw_find(uei)
        entity = extract_entity(raw)
        if entity.nil?
          raise Contractkit::NotFoundError,
                "SAM entity not found for UEI #{uei.inspect}"
        end

        ResponseParser.parse(entity)
      end

      # Pulls the first entity record out of a SAM Entities response.
      # SAM wraps responses in {entityData: [...]} for search and
      # {entityRegistration: {...}} for direct UEI lookup; handle both.
      def self.extract_entity(raw)
        return nil if raw.nil?
        return raw if raw["entityRegistration"] || raw["coreData"]
        if raw["entityData"].is_a?(Array) && !raw["entityData"].empty?
          return raw["entityData"].first
        end

        nil
      end

      # Thin client over the SAM Entities API. Mirrors the surface of
      # {Contractkit::Sam::Client} — `raw_find` + `raw_search` for the
      # two access patterns, plus an auto-paginated `search` block form.
      #
      # Query parameter names (`ueiSAM`, `samRegistered`, `page`,
      # `size`) are taken from the SAM Entity Management API v3 public
      # docs (api.sam.gov, 2026-05). Live verification was blocked by
      # SAM API daily-quota exhaustion at M4 sign-off; re-verify when
      # a cassette is recorded against a non-throttled key. See PR #42.
      class Client
        DEFAULT_PAGE_SIZE = 100

        def initialize(config: Contractkit.configuration)
          @config = config
          @connection = Contractkit::Http::Connection.build(config)
        end

        # GET /entity-information/v3/entities?ueiSAM=...
        def raw_find(uei)
          ensure_api_key!
          response = @connection.get(BASE_URL, normalize_params(ueiSAM: uei))
          handle_response(response, ueiSAM: uei)
        end

        # GET /entity-information/v3/entities with arbitrary params.
        def raw_search(**params)
          ensure_api_key!
          response = @connection.get(BASE_URL, normalize_params(params))
          handle_response(response, params)
        end

        # Auto-paginated batch interface — yields one batch (the raw
        # entityData array) per upstream page. Per #32, batches are not
        # accumulated and `limit:` caps total records.
        # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        def search(limit: nil, per_page: DEFAULT_PAGE_SIZE, **params, &block)
          return enum_for(:search, limit: limit, per_page: per_page, **params) unless block

          page = 0 # SAM Entities uses 0-indexed pages
          yielded = 0
          loop do
            raw = raw_search(**params, size: per_page, page: page)
            batch = raw["entityData"] || []
            break if batch.empty?

            batch = batch.first(limit - yielded) if limit && yielded + batch.size > limit

            yield batch
            yielded += batch.size

            break if limit && yielded >= limit

            total = raw["totalRecords"] || raw.dig("links", "totalRecords")
            break if total && yielded >= total

            page += 1
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
          params.transform_keys(&:to_sym).merge(api_key: @config.sam_api_key)
        end

        def handle_response(response, params)
          loggable = params.except(:api_key)
          snippet = response.body.to_s[0, 256]

          case response.status
          when 200..299 then parse_json(response.body, loggable)
          when 401, 403
            raise auth_error(response.status, loggable, snippet)
          when 404
            raise Contractkit::Sam::NotFoundError.new(
              "SAM entity not found",
              endpoint: BASE_URL, http_method: :get, params: loggable,
              status: 404, response_snippet: snippet
            )
          else
            raise Contractkit::Sam::ServerError.new(
              "SAM Entities returned HTTP #{response.status}",
              endpoint: BASE_URL, http_method: :get, params: loggable,
              status: response.status, response_snippet: snippet
            )
          end
        end

        def auth_error(status, params, snippet)
          Contractkit::Sam::AuthenticationError.new(
            "SAM Entities rejected API key (#{status})",
            endpoint: BASE_URL, http_method: :get, params: params,
            status: status, response_snippet: snippet
          )
        end

        def parse_json(body, loggable)
          JSON.parse(body)
        rescue JSON::ParserError => e
          raise Contractkit::Sam::MalformedResponseError.new(
            "SAM Entities returned non-JSON body: #{e.message}",
            endpoint: BASE_URL, http_method: :get, params: loggable,
            response_snippet: body.to_s[0, 256]
          )
        end
      end

      # Translates one SAM Entity record into a {Contractkit::Recipient}.
      # The SAM Entities response nests fields under several
      # sub-documents: entityRegistration, coreData (which contains
      # entityInformation, businessTypes, physicalAddress), assertions
      # (NAICS / PSC), and coreData.exclusionInformation when present.
      #
      # Field names below come from the SAM Entity Management API v3
      # public docs and the Tango research; live verification is
      # pending (SAM key was throttled at M4 sign-off — see Client
      # docstring). Parser is defensive — every accessor falls back to
      # `nil` if a key is missing, so a docs-vs-reality drift degrades
      # to missing values rather than a crash.
      module ResponseParser
        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        def self.parse(entity)
          reg = entity["entityRegistration"] || {}
          core = entity["coreData"] || {}
          info = core["entityInformation"] || {}
          biz_types = core["businessTypes"] || {}
          assertions = entity["assertions"] || {}
          gen = assertions["goodsAndServices"] || {}
          exclusion = core["exclusionInformation"] || entity["exclusionInformation"] || {}

          Contractkit::Recipient.new(
            name: reg["legalBusinessName"] || info["legalBusinessName"] || reg["dbaName"],
            uei: reg["ueiSAM"] || reg["uei"],
            duns: reg["ueiDUNS"] || reg["duns"],
            recipient_id: nil,
            registration_status: presence(reg["registrationStatus"]),
            registration_date: parse_date(reg["registrationDate"] || reg["activationDate"]),
            sam_expiration_date: parse_date(reg["registrationExpirationDate"] ||
                                            reg["expirationDate"]),
            last_update_date: parse_date(reg["lastUpdateDate"]),
            purpose_of_registration: Contractkit::CodedValue.build(
              code: reg["purposeOfRegistrationCode"],
              description: reg["purposeOfRegistrationDesc"] ||
                           reg["purposeOfRegistrationDescription"]
            ),
            cage_code: presence(reg["cageCode"]),
            dodaac: presence(reg["dodaac"]),
            legal_business_name: presence(reg["legalBusinessName"] || info["legalBusinessName"]),
            dba_name: presence(reg["dbaName"] || info["dbaName"]),
            business_types: coded_list(biz_types["businessTypeList"]),
            sba_business_types: coded_list(biz_types["sbaBusinessTypeList"]),
            naics_list: naics_list(gen["naicsList"] || gen["primaryNaics"]),
            psc_codes: psc_list(gen["pscList"]),
            exclusion_status_flag: bool_flag(reg["exclusionStatusFlag"] ||
                                             exclusion["exclusionStatusFlag"]),
            exclusion_status_description: presence(exclusion["exclusionStatusDescription"]),
            immediate_owner: owner_ref(core["immediateOwner"] || core["immediateParentEntity"]),
            highest_owner: owner_ref(core["highestLevelOwner"] || core["highestLevelEntity"]),
            predecessors: Array(core["predecessors"]).filter_map { |p| owner_ref(p) },
            raw: entity
          )
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

        class << self
          private

          def presence(value)
            return nil if value.nil?
            return nil if value.is_a?(String) && value.strip.empty?

            value
          end

          def parse_date(value)
            return value if value.is_a?(Date) && !value.is_a?(DateTime)
            return nil if value.nil? || value.to_s.strip.empty?

            Date.parse(value.to_s)
          rescue ArgumentError
            nil
          end

          def bool_flag(value)
            return nil if value.nil? || (value.is_a?(String) && value.strip.empty?)
            return value if [true, false].include?(value)

            case value.to_s.strip.downcase
            when "y", "yes", "true", "1" then true
            when "n", "no", "false", "0" then false
            end
          end

          def coded_list(list)
            Array(list).filter_map do |entry|
              Contractkit::CodedValue.build(
                code: entry["businessTypeCode"] || entry["sbaBusinessTypeCode"] || entry["code"],
                description: entry["businessTypeDesc"] || entry["sbaBusinessTypeDesc"] ||
                             entry["description"] || entry["desc"]
              )
            end
          end

          def naics_list(list)
            Array(list).map do |entry|
              {
                code: entry["naicsCode"] || entry["code"],
                description: entry["naicsDescription"] || entry["description"],
                primary: entry["isPrimary"] == "Y" || entry["primary"] == true ||
                  entry["isPrimary"] == true,
                small_business: entry["sbaSmallBusiness"] == "Y" || entry["smallBusiness"] == true
              }
            end
          end

          def psc_list(list)
            Array(list).filter_map do |entry|
              entry.is_a?(Hash) ? (entry["pscCode"] || entry["code"]) : entry
            end
          end

          def owner_ref(hash)
            return nil if hash.nil? || hash.empty?

            Contractkit::OwnerReference.new(
              uei: presence(hash["ueiSAM"] || hash["uei"]),
              name: presence(hash["legalBusinessName"] || hash["name"]),
              cage_code: presence(hash["cageCode"])
            )
          end
        end
      end
    end
  end
end
