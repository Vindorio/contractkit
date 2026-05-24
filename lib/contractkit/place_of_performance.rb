# frozen_string_literal: true

module Contractkit
  # Place-of-performance value object. Captures where contract work happens.
  #
  # The two-shape `state` normalization is the load-bearing part: SAM.gov
  # returns place_of_performance.state either as a string ("VA") or as an
  # object {"code" => "VA", "name" => "Virginia"}. Observed since at least
  # 2024. See docs/domain/sam-gov.md "placeOfPerformance.state polymorphism."
  class PlaceOfPerformance
    attr_reader :state, :city, :country, :zip

    def initialize(state: nil, city: nil, country: nil, zip: nil)
      @state   = state
      @city    = city
      @country = country
      @zip     = zip
      freeze
    end

    # @return [Hash] flat hash of all fields (for serialization).
    def to_h
      { state: state, city: city, country: country, zip: zip }
    end

    # Value-equality by full hash content (state/city/country/zip all match).
    def ==(other)
      other.is_a?(PlaceOfPerformance) && to_h == other.to_h
    end
    alias eql? ==

    # @return [Integer] hash code matching the equality contract.
    def hash
      to_h.hash
    end

    # Build a PlaceOfPerformance from a SAM.gov placeOfPerformance hash.
    # Tolerates the state polymorphism (string vs {code, name}).
    def self.from_sam(hash)
      return new if hash.nil?

      new(
        state: extract_field(hash["state"]),
        city: extract_field(hash["city"]),
        country: extract_field(hash["country"]),
        zip: hash["zip"]
      )
    end

    # Build from a USASpending award row. USASpending uses flat string keys
    # ("Place of Performance State Code", "...Country Code", "...Zip5") —
    # no polymorphism, but we keep the constructor consistent.
    def self.from_usaspending(hash)
      return new if hash.nil?

      new(
        state: hash["Place of Performance State Code"],
        country: hash["Place of Performance Country Code"],
        zip: hash["Place of Performance Zip5"]
      )
    end

    # Pulls the canonical scalar out of SAM's polymorphic state/city/country
    # field. Returns the string when the field is already a string;
    # prefers "code" over "name" when it's a hash. Code is the more useful
    # form (2-letter state, ISO country code). SAM emits string-keyed
    # JSON, so no symbol-key handling needed.
    def self.extract_field(value)
      case value
      when nil    then nil
      when String then value.empty? ? nil : value
      when Hash   then value["code"] || value["name"]
      end
    end
  end
end
