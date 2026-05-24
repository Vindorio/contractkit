# frozen_string_literal: true

require "date"

module Contractkit
  # Time-forward sibling of {Contractkit::CrossReference}. Where
  # CrossReference.awards_for asks "given this opportunity, what prior
  # awards relate?" (time-backward), Recompete.expiring asks "given the
  # near future, what IDVs and contracts are about to expire — and what
  # active solicitations might be their follow-on?" (time-forward).
  #
  # The pair is intentional: combined they let consumers see both the
  # historical incumbent picture and the upcoming recompete pipeline.
  #
  # See docs/domain/recompete.md for the join strategy, the inherent
  # imprecision (no PK across SAM ↔ USASpending), and the explicit
  # non-goal of scoring / ranking. The gem surfaces raw paired data;
  # consumers apply their own ranking.
  module Recompete
    # Default forward window — same numeric value as
    # CrossReference::DEFAULT_ENDING_WINDOW_MONTHS, kept in sync.
    DEFAULT_WINDOW_MONTHS = Contractkit::CrossReference::DEFAULT_ENDING_WINDOW_MONTHS
    # Default match keys mirror CrossReference for consistency.
    DEFAULT_MATCH = Contractkit::CrossReference::DEFAULT_MATCH

    # Paired result: an expiring award (Idv or Award) and any active
    # SAM solicitations that look like its follow-on. The match list is
    # always an Array (possibly empty — empty just means "no matches
    # found this run", not "won't recompete").
    Match = Struct.new(:award, :matching_opportunities, keyword_init: true) do
      def to_h
        {
          award: award.respond_to?(:to_h) ? award.to_h : award,
          matching_opportunities: Array(matching_opportunities).map(&:to_h)
        }
      end
    end

    class << self
      # Returns an Enumerator of {Match} (Idv or Award + matching SAM
      # opportunities). Block form yields each Match directly.
      #
      # @param within [Integer, #to_i] forward window. Accepts a plain
      #   integer (months) or any object whose #to_i is months — keeps
      #   ActiveSupport::Duration out of the gem's required surface.
      # @param match [Array<Symbol>] vocabulary identical to
      #   {Contractkit::CrossReference.awards_for}.
      # @param naics [String, Array<String>, nil] optional NAICS pre-filter.
      # @param agency [String, nil] optional agency name pre-filter.
      # @param limit [Integer] cap on expiring awards considered.
      # @param client [Contractkit::Usaspending::Client, nil]
      # @param sam_client [Contractkit::Sam::Client, nil]
      # @return [Enumerator<Match>] when no block given
      def expiring(within: DEFAULT_WINDOW_MONTHS, match: DEFAULT_MATCH,
                   naics: nil, agency: nil, limit: 100,
                   client: nil, sam_client: nil, &block)
        months = to_months(within)
        today = Date.today
        window_end = today >> months

        enum = Enumerator.new do |yielder|
          each_expiring_award(client: client, naics: naics, agency: agency,
                              today: today, window_end: window_end,
                              limit: limit) do |award|
            opps = matching_opportunities_for(award, match: match, client: sam_client)
            yielder << Match.new(award: award, matching_opportunities: opps)
          end
        end

        return enum unless block

        enum.each(&block)
      end

      private

      # Coerces `within` to integer months. Accepts plain Integer
      # (taken as months) or objects responding to :in_months (e.g.
      # ActiveSupport::Duration). No AS dependency required.
      def to_months(within)
        return within.in_months.to_i if within.respond_to?(:in_months)
        return within.to_i if within.respond_to?(:to_i)

        raise ArgumentError, "within: must be an Integer (months) or respond to :in_months"
      end

      # Yields each expiring IDV first, then each expiring definitive
      # contract. Both slices share a date filter on PoP end / last
      # date to order. Memory-bounded — never accumulates all matches.
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def each_expiring_award(client:, naics:, agency:, today:, window_end:, limit:)
        seen = 0
        date_range = [{
          "start_date" => today.iso8601,
          "end_date" => window_end.iso8601,
          "date_type" => "last_modified_date"
        }]

        base_filters = { "time_period" => date_range }
        base_filters["naics_codes"] = Array(naics) if naics
        if agency
          base_filters["agencies"] = [{ "type" => "awarding", "tier" => "toptier",
                                        "name" => agency }]
        end

        Contractkit::Idv.search(client: client, filters: base_filters, limit: limit).each do |idv|
          next unless within_window?(idv.last_date_to_order || idv.period_end_date,
                                     today: today, window_end: window_end)

          yield idv
          seen += 1
          break if seen >= limit
        end
        return if seen >= limit

        Contractkit::Award.search(client: client, filters: base_filters,
                                  limit: limit - seen).each do |award|
          next unless within_window?(award.period&.end_date,
                                     today: today, window_end: window_end)

          yield award
          seen += 1
          break if seen >= limit
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def within_window?(date, today:, window_end:)
        return false if date.nil?

        date.between?(today, window_end)
      end

      # Pulls likely follow-on SAM opportunities for an expiring award
      # using the same vocabulary as CrossReference.awards_for. Returns
      # [] on any auth / network error so one bad lookup doesn't kill
      # the whole stream.
      def matching_opportunities_for(award, match:, client:)
        params = sam_params(award, match: match)
        return [] if params.empty?

        Contractkit::Opportunity.search(client: client, **params).first(50)
      rescue Contractkit::Error
        []
      end

      def sam_params(award, match:)
        params = {}
        params[:naics] = award.naics_code if match.include?(:naics) && award.naics_code
        if match.include?(:agency) && award.awarding_agency&.name
          params[:fullParentPathName] = award.awarding_agency.name
        end
        params
      end
    end
  end
end
