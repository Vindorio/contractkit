# frozen_string_literal: true

module Contractkit
  # Federal contract recipient (the awardee). Identified by UEI since
  # 2022 (DUNS is retained on legacy awards for historical lookup).
  #
  # See docs/domain/usaspending.md "Recipient UEI vs DUNS."
  class Recipient
    attr_reader :name, :uei, :duns, :recipient_id, :raw

    def initialize(name:, uei: nil, duns: nil, recipient_id: nil, raw: nil)
      @name         = name
      @uei          = uei
      @duns         = duns
      @recipient_id = recipient_id
      @raw          = raw
      freeze
    end

    def to_h
      { name: name, uei: uei, duns: duns, recipient_id: recipient_id }
    end

    def ==(other)
      other.is_a?(Recipient) && uei == other.uei && name == other.name
    end
    alias eql? ==

    def hash
      [uei, name].hash
    end
  end
end
