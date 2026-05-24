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

    # Fetches a Recipient by UEI via USASpending's
    # /api/v2/recipient/duns/{uei}/ endpoint (the "duns" path is legacy
    # — the API moved to UEI in 2022 but kept the URL stable).
    #
    # Raises {Contractkit::NotFoundError} when the UEI isn't on file.
    def self.find(uei, client: nil)
      raw = (client || Contractkit::Usaspending::Client.new).raw_recipient(uei)

      new(
        name: raw["name"] || raw["recipient_name"],
        uei: raw["uei"] || uei,
        duns: raw["duns"],
        recipient_id: raw["recipient_id"] || raw["id"],
        raw: raw
      )
    end
  end
end
