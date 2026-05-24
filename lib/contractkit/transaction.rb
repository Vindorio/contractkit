# frozen_string_literal: true

require "bigdecimal"
require "date"

module Contractkit
  # One row from USASpending's /api/v2/transactions/ — a single
  # modification (or the base award row, which is also a transaction).
  # Per Tango research §2, option exercises and ceiling increases lack
  # explicit flags upstream; consumers infer them from #action_type
  # codes. The gem surfaces raw fields and does no inference.
  #
  # See docs/domain/transactions.md.
  class Transaction
    attr_reader :id,
                :modification_number,
                :action_date,
                :federal_action_obligation,
                :face_value_loan_guarantee,
                :original_loan_subsidy_cost,
                :action_type,
                :type,
                :description,
                :raw

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      id:,
      modification_number: nil,
      action_date: nil,
      federal_action_obligation: nil,
      face_value_loan_guarantee: nil,
      original_loan_subsidy_cost: nil,
      action_type: nil,
      type: nil,
      description: nil,
      raw: nil
    )
      @id                         = id
      @modification_number        = modification_number
      @action_date                = action_date
      @federal_action_obligation  = federal_action_obligation
      @face_value_loan_guarantee  = face_value_loan_guarantee
      @original_loan_subsidy_cost = original_loan_subsidy_cost
      @action_type                = action_type
      @type                       = type
      @description                = description
      @raw                        = raw
      freeze
    end
    # rubocop:enable Metrics/ParameterLists

    def to_h
      {
        id: id,
        modification_number: modification_number,
        action_date: action_date,
        federal_action_obligation: federal_action_obligation,
        face_value_loan_guarantee: face_value_loan_guarantee,
        original_loan_subsidy_cost: original_loan_subsidy_cost,
        action_type: action_type&.to_h,
        type: type&.to_h,
        description: description
      }
    end

    def ==(other)
      other.is_a?(Transaction) && id == other.id
    end
    alias eql? ==

    def hash
      id.hash
    end

    # Fetches all transactions for an award (auto-paginated). Returns a
    # plain Array — consumers wanting batch streaming should call
    # `client.transactions(award_id:) { |batch| ... }` directly.
    def self.for_award(award_id, client: nil, limit: nil)
      c = client || Contractkit::Usaspending::Client.new
      out = []
      c.transactions(award_id: award_id, limit: limit) do |batch|
        out.concat(Contractkit::Usaspending::ResponseParser.parse_transactions(batch))
      end
      out
    end
  end
end
