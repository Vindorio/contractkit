# frozen_string_literal: true

require "json"

module Contractkit
  # NAICS (North American Industry Classification System) value object.
  # 6-digit code, title, and sector/subsector parent links.
  #
  # See docs/domain/naics-and-setasides.md for the structure overview.
  #
  # v0.1 ships a focused procurement-relevant subset (~40 codes). Full
  # NAICS 2022 coverage (~1100 codes) is v0.2 data-only work; the
  # data-file structure is designed to absorb the expansion without an
  # interface change.
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

    def ==(other)
      other.is_a?(Naics) && code == other.code
    end
    alias eql? ==

    def hash
      code.hash
    end

    DATA_PATH = File.expand_path("data/naics_2022.json", __dir__)

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

    # Eagerly load at require-time per the AC. Memory cost is trivial
    # (~40 entries × ~5 fields).
    all
  end
end
