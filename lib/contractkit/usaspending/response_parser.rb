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
    module ResponseParser
      # rubocop:disable Metrics/AbcSize -- field mapping is inherently wide
      def self.parse(hash)
        Contractkit::Award.new(
          award_id: hash["Award ID"] || hash["generated_unique_award_id"],
          piid: hash["Award ID"],
          parent_piid: hash["parent_award_piid"],
          award_type: hash["Contract Award Type"] || hash["Award Type"],
          obligated_amount: money(hash["Award Amount"]),
          ceiling: money(hash["Base + All Options Value"]) ||
                                   money(hash["base_and_all_options_value"]),
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
      # rubocop:enable Metrics/AbcSize

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
      end
    end
  end
end
