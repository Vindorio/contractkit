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
  end
end
