# frozen_string_literal: true

module Contractkit
  # Tiny value object for fields the upstream APIs expose as a (code,
  # description) pair — e.g. `extent_competed` ("A", "FULL AND OPEN
  # COMPETITION"), `type_of_contract_pricing` ("J", "FIRM FIXED PRICE"),
  # `action_type` ("B", "SUPPLEMENTAL AGREEMENT FOR WORK WITHIN SCOPE").
  #
  # The pair is the upstream's natural shape; collapsing to just one half
  # loses information consumers may need (codes are stable, descriptions
  # are human-readable). Surface both, let the consumer pick.
  class CodedValue
    attr_reader :code, :description

    def initialize(code: nil, description: nil)
      @code        = code
      @description = description
      freeze
    end

    # @return [Hash] flat hash for serialization.
    def to_h
      { code: code, description: description }
    end

    # Value-equality by the (code, description) pair.
    def ==(other)
      other.is_a?(CodedValue) && code == other.code && description == other.description
    end
    alias eql? ==

    # @return [Integer] hash code matching the equality contract.
    def hash
      [code, description].hash
    end

    # Build from a (code, description) pair when at least one side is
    # present. Returns nil when both are blank so callers don't carry
    # empty husks around.
    def self.build(code:, description:)
      return nil if blank?(code) && blank?(description)

      new(code: presence(code), description: presence(description))
    end

    def self.presence(value)
      return nil if value.nil?
      return nil if value.is_a?(String) && value.strip.empty?

      value
    end

    def self.blank?(value)
      presence(value).nil?
    end
  end
end
