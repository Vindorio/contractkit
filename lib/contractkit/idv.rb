# frozen_string_literal: true

require "bigdecimal"
require "date"

module Contractkit
  # Indefinite-delivery vehicle (IDV / IDIQ / BPA / GWAC / BOA / FSS).
  # A USASpending "award" with `category == "idv"` — semantically a
  # contract vehicle that child contracts (task orders) order against.
  #
  # **Recompete signal:** `#last_date_to_order` is the primary expiration
  # field. When that date is within the recompete window (M4: see
  # {Contractkit::Recompete.expiring}), the vehicle is a candidate for
  # follow-on solicitation.
  #
  # See docs/domain/idvs.md for the contract / IDV split and the
  # parent/child traversal pattern.
  class Idv
    # USASpending award_type_codes for indefinite-delivery vehicles.
    IDV_AWARD_TYPE_CODES = %w[IDV_A IDV_B IDV_B_A IDV_B_B IDV_B_C IDV_C IDV_D IDV_E].freeze

    attr_reader :award_id, :piid, :parent_piid,
                :idv_type, :multiple_or_single_award_description,
                :period_start_date,
                :last_date_to_order,
                :period_end_date,
                :child_award_count,
                :child_award_total_obligation,
                :grandchild_award_count,
                :grandchild_award_total_obligation,
                :recipient,
                :awarding_agency, :awarding_subagency_name,
                :funding_agency,
                :naics_code, :psc_code,
                :description, :last_modified_at,
                :raw

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      award_id:,
      piid: nil, parent_piid: nil,
      idv_type: nil,
      multiple_or_single_award_description: nil,
      period_start_date: nil,
      last_date_to_order: nil,
      period_end_date: nil,
      child_award_count: nil,
      child_award_total_obligation: nil,
      grandchild_award_count: nil,
      grandchild_award_total_obligation: nil,
      recipient: nil,
      awarding_agency: nil, awarding_subagency_name: nil,
      funding_agency: nil,
      naics_code: nil, psc_code: nil,
      description: nil, last_modified_at: nil,
      raw: nil
    )
      @award_id    = award_id
      @piid        = piid
      @parent_piid = parent_piid

      @idv_type = idv_type
      @multiple_or_single_award_description = multiple_or_single_award_description

      @period_start_date  = period_start_date
      @last_date_to_order = last_date_to_order
      @period_end_date    = period_end_date

      @child_award_count                = child_award_count
      @child_award_total_obligation     = child_award_total_obligation
      @grandchild_award_count           = grandchild_award_count
      @grandchild_award_total_obligation = grandchild_award_total_obligation

      @recipient               = recipient
      @awarding_agency         = awarding_agency
      @awarding_subagency_name = awarding_subagency_name
      @funding_agency          = funding_agency
      @naics_code              = naics_code
      @psc_code                = psc_code
      @description             = description
      @last_modified_at        = last_modified_at
      @raw                     = raw
      freeze
    end
    # rubocop:enable Metrics/ParameterLists

    def to_h
      {
        award_id: award_id, piid: piid, parent_piid: parent_piid,
        idv_type: idv_type&.to_h,
        multiple_or_single_award_description: multiple_or_single_award_description,
        period_start_date: period_start_date,
        last_date_to_order: last_date_to_order,
        period_end_date: period_end_date,
        child_award_count: child_award_count,
        child_award_total_obligation: child_award_total_obligation,
        grandchild_award_count: grandchild_award_count,
        grandchild_award_total_obligation: grandchild_award_total_obligation,
        recipient: recipient&.to_h,
        awarding_agency: awarding_agency&.to_h,
        awarding_subagency_name: awarding_subagency_name,
        funding_agency: funding_agency&.to_h,
        naics_code: naics_code, psc_code: psc_code,
        description: description, last_modified_at: last_modified_at
      }
    end

    def ==(other)
      other.is_a?(Idv) && award_id == other.award_id
    end
    alias eql? ==

    def hash
      award_id.hash
    end

    # Transactions (modification history) for this IDV.
    def transactions(client: nil)
      Contractkit::Transaction.for_award(award_id, client: client)
    end

    # Child awards (task orders) under this IDV. Filters
    # spending_by_award by parent_piid.
    def child_awards(client: nil, limit: nil)
      c = client || Contractkit::Usaspending::Client.new
      pages = c.search(
        filters: { "filter" => { "piid" => piid }, "parent_award_piid" => piid },
        per_page: 100, limit: limit
      )
      pages.flat_map { |batch| Contractkit::Usaspending::ResponseParser.parse_batch(batch) }
    end

    # ----------------------------------------------------------------
    # Resource-module surface — convenience over the global config.
    # ----------------------------------------------------------------
    class << self
      # Lazy IdvSearch over USASpending's spending_by_award filtered to
      # IDV award type codes.
      def search(client: nil, filters: {}, fields: nil, limit: nil, per_page: nil)
        IdvSearch.new(
          client: client || default_client,
          filters: filters, fields: fields, limit: limit, per_page: per_page
        )
      end

      # Looks up an IDV by its PIID. USASpending's spending_by_award
      # accepts a `keywords` filter that matches PIIDs in practice; we
      # find the first IDV-category result.
      def find_by_piid(piid, client: nil)
        result = search(client: client, filters: { "keywords" => [piid] }, limit: 25).first(25)
        result.find { |idv| idv.piid == piid } || result.first
      end

      private

      def default_client
        Contractkit::Usaspending::Client.new
      end
    end
  end
end
