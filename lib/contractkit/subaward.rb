# frozen_string_literal: true

require "bigdecimal"
require "date"

module Contractkit
  # One subaward row. Surfaces both sides (prime + sub) per Tango §4 so
  # callers can query teaming patterns in either direction. Multi-tier
  # (sub-to-sub) is not in USASpending and is not exposed here.
  #
  # Caveat: subaward reporting is required for awards > $30k (FFATA).
  # Smaller awards have no subaward records; reporting compliance is
  # imperfect even above that threshold.
  #
  # See docs/domain/subawards.md.
  class Subaward
    attr_reader :id, :subaward_number, :action_date, :amount, :description,
                :prime_award_id, :prime_award_piid,
                :prime_recipient_uei, :prime_recipient_name,
                :sub_recipient_uei, :sub_recipient_name, :sub_recipient_address,
                :naics_code, :psc_code,
                :raw

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      id:,
      subaward_number: nil, action_date: nil, amount: nil, description: nil,
      prime_award_id: nil, prime_award_piid: nil,
      prime_recipient_uei: nil, prime_recipient_name: nil,
      sub_recipient_uei: nil, sub_recipient_name: nil, sub_recipient_address: {},
      naics_code: nil, psc_code: nil,
      raw: nil
    )
      @id                    = id
      @subaward_number       = subaward_number
      @action_date           = action_date
      @amount                = amount
      @description           = description
      @prime_award_id        = prime_award_id
      @prime_award_piid      = prime_award_piid
      @prime_recipient_uei   = prime_recipient_uei
      @prime_recipient_name  = prime_recipient_name
      @sub_recipient_uei     = sub_recipient_uei
      @sub_recipient_name    = sub_recipient_name
      @sub_recipient_address = (sub_recipient_address || {}).freeze
      @naics_code            = naics_code
      @psc_code              = psc_code
      @raw                   = raw
      freeze
    end
    # rubocop:enable Metrics/ParameterLists

    def to_h
      {
        id: id,
        subaward_number: subaward_number,
        action_date: action_date,
        amount: amount,
        description: description,
        prime_award_id: prime_award_id,
        prime_award_piid: prime_award_piid,
        prime_recipient_uei: prime_recipient_uei,
        prime_recipient_name: prime_recipient_name,
        sub_recipient_uei: sub_recipient_uei,
        sub_recipient_name: sub_recipient_name,
        sub_recipient_address: sub_recipient_address,
        naics_code: naics_code,
        psc_code: psc_code
      }
    end

    def ==(other)
      other.is_a?(Subaward) && id == other.id
    end
    alias eql? ==

    def hash
      id.hash
    end

    # Fetches all subawards for a prime award (auto-paginated).
    def self.for_award(award_id, client: nil, limit: nil)
      c = client || Contractkit::Usaspending::Client.new
      out = []
      filters = { "award_id" => award_id }
      c.subawards(filters: filters, limit: limit) do |batch|
        out.concat(Contractkit::Usaspending::ResponseParser.parse_subawards(batch))
      end
      out
    end

    # Search subawards by arbitrary USASpending filter hash. Returns an
    # Enumerator (record-level) when no block; yields batches when a
    # block is given.
    def self.search(filters: {}, client: nil, limit: nil, per_page: nil, &block)
      c = client || Contractkit::Usaspending::Client.new
      enum = Enumerator.new do |y|
        c.subawards(filters: filters, limit: limit, per_page: per_page || 100) do |batch|
          Contractkit::Usaspending::ResponseParser.parse_subawards(batch).each { |s| y << s }
        end
      end
      return enum unless block

      enum.each(&block)
    end
  end
end
