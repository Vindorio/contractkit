# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"
require "date"

module Contractkit
  module Fpds
    # Translates one SAM.gov Contract Awards API result (one element of
    # `awardSummary`) into a {Contractkit::Award} value object.
    #
    # The SAM.gov Contract Awards API is the canonical successor to the
    # decommissioned FPDS ATOM feed. It uses a deeply-nested JSON
    # structure with sections (contractId, coreData, awardDetails,
    # awardeeData, transactionData).
    #
    # Key differences from USASpending:
    # - PIID comes from contractId.piid (not "Award ID")
    # - Award ID is contractId.piid + modificationNumber (no
    #   generated_unique_award_id at this API level)
    # - Agency data is nested under coreData.federalOrganization
    # - NAICS/PSC are in coreData.productOrServiceInformation
    # - Obligated amount is in awardDetails.dollars.actionObligation
    # rubocop:disable Metrics/ModuleLength
    module ResponseParser
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def self.parse(hash)
        contract_id = hash["contractId"] || {}
        core = hash["coreData"] || {}
        details = hash["awardDetails"] || {}
        awardee = details["awardeeData"] || {}
        dollars = details["dollars"] || {}
        total_dollars = details["totalContractDollars"] || {}
        dates = details["dates"] || {}
        pop = core["principalPlaceOfPerformance"] || {}
        psc_info = core["productOrServiceInformation"] || {}
        comp_info = core["competitionInformation"] || {}
        tx_data = details["transactionData"] || {}
        federal_org = core["federalOrganization"] || {}
        contracting = federal_org["contractingInformation"] || {}
        funding = federal_org["fundingInformation"] || {}

        piid = contract_id["piid"]
        mod_number = contract_id["modificationNumber"]

        Contractkit::Award.new(
          award_id: [piid, mod_number].compact.join("-"),
          piid: piid,
          parent_piid: contract_id.dig("referencedIDVPiid"),
          award_type: core.dig("awardOrIDVType", "name") || core["awardOrIDV"],
          obligated_amount: money(dollars["actionObligation"]),
          ceiling: money(total_dollars["totalBaseAndAllOptionsValue"]) ||
                   money(dollars["baseAndAllOptionsValue"]),
          base_and_all_options_value: money(total_dollars["totalBaseAndAllOptionsValue"]) ||
                                      money(dollars["baseAndAllOptionsValue"]),
          base_and_exercised_options_value: money(total_dollars["totalBaseAndExercisedOptionsValue"]) ||
                                            money(dollars["baseAndExercisedOptionsValue"]),
          total_contract_value: money(total_dollars["totalBaseAndAllOptionsValue"]) ||
                                money(dollars["baseAndAllOptionsValue"]),
          total_obligation: money(total_dollars["totalActionObligation"]) ||
                            money(dollars["actionObligation"]),
          number_of_offers_received: integer(details.dig("competitionInformation",
                                                      "idvNumberOfOffersReceived")),
          extent_competed: coded_value(comp_info["extentCompeted"]),
          type_of_contract_pricing: coded_value(
            core.dig("acquisitionData", "typeOfContractPricing")
          ),
          contract_award_type: coded_value(core["awardOrIDVType"]),
          solicitation_procedures: coded_value(comp_info["solicitationProcedures"]),
          recipient: parse_recipient(awardee),
          awarding_agency: Contractkit::Agency.normalize(
            contracting.dig("contractingDepartment", "name")
          ),
          awarding_subagency_name: presence(
            contracting.dig("contractingSubtier", "name")
          ),
          funding_agency: Contractkit::Agency.normalize(
            funding.dig("fundingDepartment", "name")
          ),
          naics_code: parse_naics(psc_info["principalNaics"]),
          psc_code: presence(psc_info.dig("productOrService", "code")),
          set_aside_code: presence(
            details.dig("preferenceProgramsInformation",
                        "contractingOfficerBusinessSizeDetermination")&.first&.dig("code")
          ),
          set_aside: parse_set_aside(details),
          period: Contractkit::Period.new(
            start_date: dates["periodOfPerformanceStartDate"],
            end_date: dates["currentCompletionDate"]
          ),
          place_of_performance: Contractkit::PlaceOfPerformance.new(
            state: presence(pop.dig("state", "code")),
            city: presence(pop.dig("city", "name")),
            country: presence(pop.dig("country", "code")),
            zip: presence(pop["zipCode"])
          ),
          description: presence(
            details.dig("productOrServiceInformation", "descriptionOfContractRequirement")
          ),
          last_modified_at: presence(tx_data["lastModifiedDate"]),
          raw: hash
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def self.parse_batch(batch)
        batch.map { |row| parse(row) }
      end

      class << self
        private

        def presence(value)
          return nil if value.nil?
          return nil if value.is_a?(String) && value.strip.empty?

          value
        end

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

        # Parse principal NAICS from the array form: [{"code"=>"...","name"=>"..."}]
        def parse_naics(naics_array)
          return nil if naics_array.nil? || naics_array.empty?

          naics_array.first["code"] || naics_array.first[:code]
        end

        def parse_recipient(awardee)
          header = awardee["awardeeHeader"] || {}
          uei_info = awardee["awardeeUEIInformation"] || {}
          name = presence(header["awardeeName"] || header["legalBusinessName"])
          return nil if name.nil?

          Contractkit::Recipient.new(
            name: name,
            uei: presence(uei_info["uniqueEntityId"]),
            duns: nil, # SAM.gov Contract Awards API doesn't expose DUNS
            recipient_id: presence(uei_info["uniqueEntityId"]),
            raw: awardee
          )
        end

        def parse_set_aside(details)
          pref = details.dig("preferenceProgramsInformation") || {}
          bus_size = pref["contractingOfficerBusinessSizeDetermination"]
          return nil if bus_size.nil? || bus_size.empty?

          Contractkit::SetAside.safe_normalize(bus_size.first["name"])
        end

        def coded_value(hash)
          return nil if hash.nil? || hash.empty?

          Contractkit::CodedValue.build(
            code: hash["code"],
            description: hash["name"] || hash["description"]
          )
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
