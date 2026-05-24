# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"
require "date"

module Contractkit
  module Usaspending
    # Translates one USASpending award hash (one element of `results`
    # from spending_by_award) into a {Contractkit::Award} value object.
    #
    # USASpending uses human-readable field names with spaces ("Award ID",
    # "Recipient Name") — that's their JSON schema, not a misnomer. Keep
    # the string keys verbatim.
    #
    # M4 (#36): also handles the single-award **detail** endpoint
    # response shape via {.parse_detail} — that endpoint uses underscored
    # snake_case keys ("piid", "total_obligation") and nests competition
    # and pricing fields under `latest_transaction_contract_data`. The
    # full pricing + competition surface is only available on the detail
    # endpoint; the bulk parser leaves those fields nil.
    # rubocop:disable Metrics/ModuleLength -- this module is one big field-mapping table by design
    module ResponseParser
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- field mapping is inherently wide
      def self.parse(hash)
        Contractkit::Award.new(
          award_id: hash["Award ID"] || hash["generated_unique_award_id"],
          piid: hash["Award ID"],
          parent_piid: hash["parent_award_piid"],
          award_type: hash["Contract Award Type"] || hash["Award Type"],
          obligated_amount: money(hash["Award Amount"]),
          ceiling: money(hash["Base + All Options Value"]) ||
                                   money(hash["base_and_all_options_value"]),
          base_and_all_options_value: money(hash["Base + All Options Value"]) ||
                                      money(hash["base_and_all_options_value"]),
          base_and_exercised_options_value: money(hash["Base + Exercised Options Value"]) ||
                                            money(hash["base_and_exercised_options_value"]),
          total_contract_value: money(hash["Total Contract Value"]) ||
                                money(hash["total_contract_value"]),
          total_obligation: money(hash["Total Obligation"]) ||
                            money(hash["total_obligation"]) ||
                            money(hash["Award Amount"]),
          # Competition + pricing CodedValues are detail-endpoint-only on
          # the bulk path; leave nil. parse_detail populates them.
          number_of_offers_received: nil,
          extent_competed: nil,
          type_of_contract_pricing: nil,
          contract_award_type: Contractkit::CodedValue.build(
            code: hash["contract_award_type"],
            description: hash["Contract Award Type"] || hash["Award Type"]
          ),
          solicitation_procedures: nil,
          recipient: parse_recipient(hash),
          awarding_agency: Contractkit::Agency.normalize(hash["Awarding Agency"]),
          awarding_subagency_name: presence(hash["Awarding Sub Agency"]),
          funding_agency: Contractkit::Agency.normalize(hash["Funding Agency"]),
          naics_code: presence(hash["NAICS"]),
          psc_code: presence(hash["PSC"]),
          set_aside_code: presence(hash["Type of Set Aside"]),
          set_aside: Contractkit::SetAside.safe_normalize(
            hash["Type of Set Aside"] || hash["type_set_aside"]
          ),
          period: Contractkit::Period.new(
            start_date: hash["Start Date"],
            end_date: hash["End Date"]
          ),
          place_of_performance: Contractkit::PlaceOfPerformance.from_usaspending(hash),
          description: presence(hash["Description"]),
          last_modified_at: presence(hash["Last Modified Date"]),
          raw: hash
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def self.parse_batch(batch)
        batch.map { |row| parse(row) }
      end

      # Parses one spending_by_award row into a {Contractkit::Idv}.
      # USASpending uses the same row shape for IDVs as contracts on the
      # search endpoint — the difference is the `award_type_codes`
      # filter the caller used.
      #
      # Field-name notes (verified against live USASpending responses,
      # 2026-05):
      # - The IDV "type" code lives at top-level `hash["type"]` (e.g.
      #   "IDV_C"); there is no `idv_type` key. `idv_type_description`
      #   does live under `latest_transaction_contract_data`.
      # - "Last Date To Order" only appears on the spending_by_award
      #   search response (often null even there). The detail endpoint
      #   exposes no equivalent — fall back to
      #   period_of_performance.potential_end_date, then end_date, so
      #   the recompete helper still gets a usable expiration signal.
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def self.parse_idv(hash)
        contract = hash["latest_transaction_contract_data"] || {}
        period_hash = hash["period_of_performance"] || {}

        Contractkit::Idv.new(
          award_id: hash["Award ID"] || hash["generated_unique_award_id"] || hash["id"],
          piid: hash["Award ID"] || hash["piid"],
          parent_piid: hash["parent_award_piid"] || hash["parent_award_id"],
          idv_type: Contractkit::CodedValue.build(
            code: hash["type"] || hash["idv_type"] || contract["idv_type"],
            description: hash["type_description"] || hash["idv_type_description"] ||
                         contract["idv_type_description"]
          ),
          multiple_or_single_award_description:
            presence(hash["multiple_or_single_award_description"] ||
                     contract["multiple_or_single_award_description"]),
          period_start_date: parse_date(hash["Start Date"] || period_hash["start_date"]),
          last_date_to_order: parse_date(hash["Last Date To Order"] ||
                                         contract["ordering_period_end_date"] ||
                                         period_hash["last_date_to_order"] ||
                                         period_hash["potential_end_date"]),
          period_end_date: parse_date(hash["End Date"] || period_hash["end_date"]),
          child_award_count: integer(hash["child_award_count"]),
          child_award_total_obligation: money(hash["child_award_total_obligation"]),
          grandchild_award_count: integer(hash["grandchild_award_count"]),
          grandchild_award_total_obligation: money(hash["grandchild_award_total_obligation"]),
          recipient: parse_recipient(hash) || parse_recipient_detail(hash["recipient"] || {}),
          awarding_agency: Contractkit::Agency.normalize(
            hash["Awarding Agency"] ||
            hash.dig("awarding_agency", "toptier_agency", "name")
          ),
          awarding_subagency_name: presence(hash["Awarding Sub Agency"]),
          funding_agency: Contractkit::Agency.normalize(
            hash["Funding Agency"] ||
            hash.dig("funding_agency", "toptier_agency", "name")
          ),
          naics_code: presence(hash["NAICS"] || contract["naics"]),
          psc_code: presence(hash["PSC"] || contract["product_or_service_code"]),
          description: presence(hash["Description"] || hash["description"]),
          last_modified_at: presence(hash["Last Modified Date"]),
          raw: hash
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def self.parse_idv_batch(batch)
        batch.map { |row| parse_idv(row) }
      end

      # Parses one /api/v2/transactions/ result row into a Transaction.
      def self.parse_transaction(hash)
        Contractkit::Transaction.new(
          id: hash["id"],
          modification_number: presence(hash["modification_number"]),
          action_date: parse_date(hash["action_date"]),
          federal_action_obligation: money(hash["federal_action_obligation"]),
          face_value_loan_guarantee: money(hash["face_value_loan_guarantee"]),
          original_loan_subsidy_cost: money(hash["original_loan_subsidy_cost"]),
          action_type: Contractkit::CodedValue.build(
            code: hash["action_type"],
            description: hash["action_type_description"]
          ),
          type: Contractkit::CodedValue.build(
            code: hash["type"],
            description: hash["type_description"]
          ),
          description: presence(hash["description"]),
          raw: hash
        )
      end

      def self.parse_transactions(batch)
        batch.map { |row| parse_transaction(row) }
      end

      # Parses one subaward row into a {Contractkit::Subaward}.
      #
      # The live per-award endpoint (POST /api/v2/subawards/) returns
      # snake_case keys and a sparse field set: id, subaward_number,
      # description, action_date, amount, recipient_name. Prime
      # metadata and recipient UEIs are not included.
      #
      # The legacy spending_by_subaward shape (spaced keys like
      # "Sub-Award ID") is still accepted via fallbacks below in case
      # USASpending re-introduces a bulk endpoint.
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def self.parse_subaward(hash)
        Contractkit::Subaward.new(
          id: hash["internal_id"] || hash["id"],
          subaward_number: presence(hash["Sub-Award ID"] || hash["subaward_number"]),
          action_date: parse_date(hash["Sub-Award Date"] || hash["action_date"]),
          amount: money(hash["Sub-Award Amount"] || hash["amount"] || hash["subaward_amount"]),
          description: presence(hash["Sub-Award Description"] || hash["description"]),
          prime_award_id: presence(hash["prime_award_generated_internal_id"] ||
                                   hash["prime_award_internal_id"]),
          prime_award_piid: presence(hash["Prime Award ID"] || hash["prime_award_piid"]),
          prime_recipient_uei: presence(hash["Prime Recipient UEI"] || hash["prime_recipient_uei"]),
          prime_recipient_name: presence(hash["Prime Recipient Name"] ||
                                         hash["prime_recipient_name"]),
          sub_recipient_uei: presence(hash["Sub-Recipient UEI"] || hash["recipient_uei"]),
          sub_recipient_name: presence(hash["Sub-Recipient Name"] || hash["recipient_name"]),
          sub_recipient_address: {
            city: presence(hash["Sub-Recipient City"] || hash["recipient_location_city_name"]),
            state: presence(hash["Sub-Recipient State"] || hash["recipient_location_state_code"]),
            country: presence(hash["Sub-Recipient Country"] ||
                              hash["recipient_location_country_code"])
          }.compact,
          naics_code: presence(hash["NAICS"] || hash["naics"]),
          psc_code: presence(hash["PSC"] || hash["product_or_service_code"]),
          raw: hash
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def self.parse_subawards(batch)
        batch.map { |row| parse_subaward(row) }
      end

      # Parses one USASpending `/api/v2/awards/{id}/` detail response
      # into a {Contractkit::Award} with the full competition + pricing
      # surface populated. The detail endpoint uses snake_case keys and
      # nests contract-data fields under `latest_transaction_contract_data`.
      #
      # Field positions verified against live USASpending responses,
      # 2026-05. Money fields land at top-level (`base_and_all_options`,
      # `base_exercised_options`, `total_obligation`); competition
      # fields nest under `latest_transaction_contract_data`. There is
      # no separate `total_contract_value` key — it equals
      # `base_and_all_options` for both definitive contracts and IDVs.
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def self.parse_detail(hash)
        contract = hash["latest_transaction_contract_data"] || {}
        period_hash = hash["period_of_performance"] || {}
        awarding = hash["awarding_agency"] || {}
        funding = hash["funding_agency"] || {}
        recipient_hash = hash["recipient"] || {}

        Contractkit::Award.new(
          award_id: hash["generated_unique_award_id"] || hash["id"],
          piid: hash["piid"],
          parent_piid: hash["parent_award_piid"] || hash["parent_award_piid_x"],
          award_type: hash["type_description"] || hash["category"],
          obligated_amount: money(hash["total_obligation"]),
          ceiling: money(hash["base_and_all_options"]) ||
                                   money(contract["base_and_all_options_value"]),
          base_and_all_options_value: money(hash["base_and_all_options"]) ||
                                      money(contract["base_and_all_options_value"]),
          base_and_exercised_options_value: money(hash["base_exercised_options"]) ||
                                            money(contract["base_exercised_options_val"]),
          total_contract_value: money(hash["total_contract_value"]) ||
                                money(contract["total_contract_value"]) ||
                                money(hash["base_and_all_options"]),
          total_obligation: money(hash["total_obligation"]),
          number_of_offers_received: integer(contract["number_of_offers_received"]),
          extent_competed: Contractkit::CodedValue.build(
            code: contract["extent_competed"],
            description: contract["extent_competed_description"]
          ),
          type_of_contract_pricing: Contractkit::CodedValue.build(
            code: contract["type_of_contract_pricing"],
            description: contract["type_of_contract_pric_desc"] ||
                         contract["type_of_contract_pricing_description"]
          ),
          contract_award_type: Contractkit::CodedValue.build(
            code: hash["type"],
            description: hash["type_description"]
          ),
          solicitation_procedures: Contractkit::CodedValue.build(
            code: contract["solicitation_procedures"],
            description: contract["solicitation_procedures_description"]
          ),
          recipient: parse_recipient_detail(recipient_hash),
          awarding_agency: Contractkit::Agency.normalize(
            awarding.dig("toptier_agency", "name") || awarding["name"]
          ),
          awarding_subagency_name: presence(awarding.dig("subtier_agency", "name")),
          funding_agency: Contractkit::Agency.normalize(
            funding.dig("toptier_agency", "name") || funding["name"]
          ),
          naics_code: presence(contract["naics"] || hash["naics_code"]),
          psc_code: presence(contract["product_or_service_code"] || hash["psc_code"]),
          set_aside_code: presence(contract["type_set_aside"]),
          set_aside: Contractkit::SetAside.safe_normalize(contract["type_set_aside"]),
          period: Contractkit::Period.new(
            start_date: period_hash["start_date"],
            end_date: period_hash["end_date"]
          ),
          place_of_performance: parse_pop_detail(hash["place_of_performance"]),
          description: presence(hash["description"]),
          last_modified_at: presence(hash["date_signed"] || hash["last_modified_date"]),
          raw: hash
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

        # USASpending money fields can be a Number, a numeric String,
        # or nil. Normalize to BigDecimal for cent-precision arithmetic.
        def money(value)
          return nil if value.nil?
          return value if value.is_a?(BigDecimal)
          return BigDecimal(value.to_s) if value.is_a?(Numeric)

          str = value.to_s.strip
          return nil if str.empty?

          BigDecimal(str)
        rescue ArgumentError, TypeError
          nil
        end

        def parse_date(value)
          return value if value.is_a?(Date) && !value.is_a?(DateTime)
          return nil if value.nil? || value.to_s.strip.empty?

          Date.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        # Permissive Integer parse — accepts Integer, numeric String, or nil.
        def integer(value)
          return nil if value.nil?
          return value if value.is_a?(Integer)
          return value.to_i if value.is_a?(Numeric)

          str = value.to_s.strip
          return nil if str.empty?

          Integer(str)
        rescue ArgumentError, TypeError
          nil
        end

        def parse_recipient(hash)
          name = presence(hash["Recipient Name"])
          return nil if name.nil?

          Contractkit::Recipient.new(
            name: name,
            uei: presence(hash["Recipient UEI"]),
            duns: presence(hash["Recipient DUNS"]),
            recipient_id: presence(hash["recipient_id"]),
            raw: hash
          )
        end

        def parse_recipient_detail(hash)
          name = presence(hash["recipient_name"] || hash["name"])
          return nil if name.nil?

          Contractkit::Recipient.new(
            name: name,
            uei: presence(hash["recipient_uei"] || hash["uei"]),
            duns: presence(hash["recipient_unique_id"] || hash["duns"]),
            recipient_id: presence(hash["recipient_id"] || hash["id"]),
            raw: hash
          )
        end

        def parse_pop_detail(hash)
          return Contractkit::PlaceOfPerformance.new if hash.nil?

          Contractkit::PlaceOfPerformance.new(
            state: presence(hash["state_code"]),
            city: presence(hash["city_name"]),
            country: presence(hash["country_code"] || hash["country_name"]),
            zip: presence(hash["zip5"] || hash["zip"])
          )
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
