# frozen_string_literal: true

module Contractkit
  # Join SAM opportunities to USASpending awards. The two systems share
  # no primary key — see docs/domain/cross-referencing.md for the full
  # rationale of why agency+NAICS is the workhorse join.
  module CrossReference
    DEFAULT_LOOKBACK_YEARS = 5
    DEFAULT_ENDING_WINDOW_MONTHS = 24
    DEFAULT_MATCH = %i[agency naics].freeze
    DEFAULT_LIMIT = 50

    # Returns awards likely related to the given opportunity. Default
    # match keys are agency + NAICS; pass :psc to add PSC as a tightener
    # or :state to constrain by place of performance.
    #
    # @param opportunity [Contractkit::Opportunity]
    # @param lookback [Integer] years of historical awards to query
    # @param ending_window [Integer] months — reserved for v0.2 recompete
    #   refinement; currently informational (USASpending doesn't expose a
    #   period-end filter on spending_by_award).
    # @param match [Array<Symbol>] one or more of [:agency, :naics, :psc, :state]
    # @param limit [Integer] cap on total awards returned
    # @param client [Contractkit::Usaspending::Client, nil]
    # @return [Array<Contractkit::Award>]
    def self.awards_for(opportunity:, lookback: DEFAULT_LOOKBACK_YEARS,
                        ending_window: DEFAULT_ENDING_WINDOW_MONTHS,
                        match: DEFAULT_MATCH, limit: DEFAULT_LIMIT, client: nil)
      _ = ending_window # reserved; see @param above

      filters = build_filters(opportunity: opportunity, lookback: lookback, match: match)
      Contractkit::Award
        .search(client: client, filters: filters, limit: limit, per_page: [limit, 100].min)
        .first(limit)
    end

    # Single-recipient dominance heuristic. Returns the Recipient when
    # one entity holds > 50% of the obligation across `awards`, nil
    # otherwise (multi-award IDIQ — ambiguous; never force a guess).
    # See docs/domain/cross-referencing.md "What 'incumbent' looks like."
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def self.likely_incumbent(awards)
      return nil if awards.empty?

      buckets = group_by_recipient(awards)
      return nil if buckets.empty?

      totals = buckets.transform_values do |list|
        list.sum(BigDecimal("0")) do |a|
          a.obligated_amount || 0
        end
      end
      grand_total = totals.values.sum(BigDecimal("0"))
      return nil if grand_total.zero?

      dominant_key, dominant_total = totals.max_by { |_, t| t }
      return nil unless dominant_total > (grand_total / 2)

      buckets[dominant_key].first.recipient
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    class << self
      private

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def build_filters(opportunity:, lookback:, match:)
        filters = {
          "time_period" => time_window(lookback)
        }

        if match.include?(:agency) && opportunity.agency&.name
          filters["agencies"] = [{
            "type" => "awarding",
            "tier" => "toptier",
            "name" => opportunity.agency.name
          }]
        end

        if match.include?(:naics) && opportunity.naics_code
          filters["naics_codes"] =
            [opportunity.naics_code]
        end
        if match.include?(:psc) && opportunity.psc_code
          filters["psc_codes"]   =
            [opportunity.psc_code]
        end
        if match.include?(:state) && opportunity.place_of_performance&.state
          filters["place_of_performance_locations"] = [
            { "country" => "USA", "state" => opportunity.place_of_performance.state }
          ]
        end

        filters
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def time_window(lookback_years)
        today = Date.today
        [{
          "start_date" => (today - (lookback_years * 365)).iso8601,
          "end_date" => today.iso8601
        }]
      end

      def group_by_recipient(awards)
        awards.each_with_object({}) do |award, acc|
          key = award.recipient&.uei || award.recipient&.name
          next unless key

          (acc[key] ||= []) << award
        end
      end
    end
  end
end
