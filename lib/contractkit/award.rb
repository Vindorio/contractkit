# frozen_string_literal: true

require "bigdecimal"

module Contractkit
  # Normalized USASpending.gov award. Plain Ruby value object — see
  # docs/design/data-models.md for the field map.
  #
  # Money fields: #obligated_amount is the headline (sum of obligations
  # to date, BigDecimal); #ceiling is the contract's ceiling (Base + All
  # Options Value) exposed separately so callers don't confuse the two.
  class Award
    attr_reader :award_id, :piid, :parent_piid, :award_type,
                :obligated_amount, :ceiling,
                :recipient,
                :awarding_agency, :awarding_subagency_name,
                :funding_agency,
                :naics_code, :psc_code,
                :set_aside_code, :set_aside,
                :period,
                :place_of_performance,
                :description, :last_modified_at,
                :raw

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      award_id:,
      piid: nil, parent_piid: nil, award_type: nil,
      obligated_amount: nil, ceiling: nil,
      recipient: nil,
      awarding_agency: nil, awarding_subagency_name: nil,
      funding_agency: nil,
      naics_code: nil, psc_code: nil,
      set_aside_code: nil, set_aside: :none,
      period: nil,
      place_of_performance: nil,
      description: nil, last_modified_at: nil,
      raw: nil
    )
      @award_id                = award_id
      @piid                    = piid
      @parent_piid             = parent_piid
      @award_type              = award_type
      @obligated_amount        = obligated_amount
      @ceiling                 = ceiling
      @recipient               = recipient
      @awarding_agency         = awarding_agency
      @awarding_subagency_name = awarding_subagency_name
      @funding_agency          = funding_agency
      @naics_code              = naics_code
      @psc_code                = psc_code
      @set_aside_code          = set_aside_code
      @set_aside               = set_aside
      @period                  = period
      @place_of_performance    = place_of_performance
      @description             = description
      @last_modified_at        = last_modified_at
      @raw                     = raw
      freeze
    end
    # rubocop:enable Metrics/ParameterLists

    def to_h
      {
        award_id: award_id,
        piid: piid,
        parent_piid: parent_piid,
        award_type: award_type,
        obligated_amount: obligated_amount,
        ceiling: ceiling,
        recipient: recipient&.to_h,
        awarding_agency: awarding_agency&.to_h,
        awarding_subagency_name: awarding_subagency_name,
        funding_agency: funding_agency&.to_h,
        naics_code: naics_code,
        psc_code: psc_code,
        set_aside_code: set_aside_code,
        set_aside: set_aside,
        period: period&.to_h,
        place_of_performance: place_of_performance&.to_h,
        description: description,
        last_modified_at: last_modified_at
      }
    end

    def ==(other)
      other.is_a?(Award) && award_id == other.award_id
    end
    alias eql? ==

    def hash
      award_id.hash
    end

    # ----------------------------------------------------------------
    # Resource-module surface — convenience over the global config.
    # ----------------------------------------------------------------

    class << self
      # Lazy AwardSearch over USASpending's spending_by_award.
      def search(client: nil, filters: {}, fields: nil, limit: nil, per_page: nil)
        AwardSearch.new(
          client: client || default_client,
          filters: filters, fields: fields, limit: limit, per_page: per_page
        )
      end

      # Yields each Award whose action_date falls on or after `time`.
      # USASpending has no "last modified" filter; the `time_period`
      # filter on action_date is the closest equivalent.
      def updated_since(time, client: nil, filters: {}, **, &block)
        merged = filters.merge(
          "time_period" => [{
            "start_date" => to_date(time).iso8601,
            "end_date" => Date.today.iso8601
          }]
        )
        result = search(client: client, filters: merged, **)
        return result.each(&block) if block

        result
      end

      # Fetches a single Award by its generated_unique_award_id.
      #
      # **v0.2:** USASpending's `/api/v2/awards/{id}/` endpoint returns
      # a different JSON shape than spending_by_award (nested toptier/
      # subtier agency objects, recipient sub-document, no spaces in
      # keys). A separate parser path is required. Deferred to v0.2
      # because it isn't a blocker for the v0.1 dogfood — Vindor uses
      # filtered search and locates by award_id in the results.
      def find(_award_id, client: nil)
        raise NotImplementedError,
              "Award.find is deferred to v0.2. USASpending's /api/v2/awards/{id}/ " \
              "endpoint returns a different JSON shape than spending_by_award; " \
              "a separate parser path is needed. For now, use Award.search with a " \
              "piid or recipient_uei filter and locate by award_id in the results."
      end

      private

      def default_client
        Contractkit::Usaspending::Client.new
      end

      def to_date(value)
        return value if value.is_a?(Date) && !value.is_a?(DateTime)

        value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
      end
    end
  end
end
