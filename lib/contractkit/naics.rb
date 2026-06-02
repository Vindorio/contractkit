# frozen_string_literal: true

require "json"

module Contractkit
  # NAICS (North American Industry Classification System) value object.
  # 6-digit code, title, and sector/subsector parent links.
  #
  # See docs/domain/naics-and-setasides.md for the structure overview.
  #
  # Ships the full NAICS 2022 dictionary — all 1,012 6-digit codes with
  # sector and subsector parents, sourced from the Census Bureau's official
  # 2022 NAICS Structure file.
  class Naics
    attr_reader :code, :title, :sector_code, :sector_title,
                :subsector_code, :subsector_title

    def initialize(code:, title:, sector_code: nil, sector_title: nil,
                   subsector_code: nil, subsector_title: nil)
      @code            = code
      @title           = title
      @sector_code     = sector_code
      @sector_title    = sector_title
      @subsector_code  = subsector_code
      @subsector_title = subsector_title
      freeze
    end

    # @return [Hash] flat hash of all fields (for serialization).
    def to_h
      {
        code: code, title: title,
        sector_code: sector_code, sector_title: sector_title,
        subsector_code: subsector_code, subsector_title: subsector_title
      }
    end

    # The sector parent as its own Naics value (2-digit code).
    def sector
      return nil unless sector_code

      Naics.new(code: sector_code, title: sector_title)
    end

    # The subsector parent (3-digit code).
    def subsector
      return nil unless subsector_code

      Naics.new(
        code: subsector_code, title: subsector_title,
        sector_code: sector_code, sector_title: sector_title
      )
    end

    # Value-equality by 6-digit code.
    def ==(other)
      other.is_a?(Naics) && code == other.code
    end
    alias eql? ==

    # @return [Integer] hash code matching the equality contract.
    def hash
      code.hash
    end

    # Path to the shipped NAICS 2022 full data file (see {Contractkit::Naics.all}).
    DATA_PATH = File.expand_path("data/naics_2022_full.json", __dir__)

    class << self
      # Returns the Naics value object for the given 6-digit code, or nil
      # if the code isn't in the shipped table.
      def lookup(code)
        index[code.to_s]
      end

      # Frozen array of every shipped Naics entry. Useful for seeding
      # consumer reference tables.
      def all
        @all ||= index.values.freeze
      end

      private

      def index
        @index ||= build_index
      end

      def build_index
        data = JSON.parse(File.read(DATA_PATH))
        sectors = data["sectors"]
        subsectors = data["subsectors"]

        result = data["entries"].to_h do |entry|
          code = entry["code"]
          sc = entry["sector_code"]
          ssc = entry["subsector_code"]
          [
            code,
            new(
              code: code, title: entry["title"],
              sector_code: sc, sector_title: sectors[sc],
              subsector_code: ssc, subsector_title: subsectors[ssc]
            )
          ]
        end
        result.freeze
      end
    end

    # Eagerly load at require-time. Memory cost is acceptable
    # (~1,012 entries × ~5 fields ≈ trivial).
    all
  end
end
