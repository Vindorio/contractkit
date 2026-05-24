# frozen_string_literal: true

require "json"

module Contractkit
  # Product and Service Code (PSC) value object. Federal procurement
  # taxonomy of what's being bought, complementary to NAICS (which says
  # who's doing the buying).
  #
  # See docs/domain/naics-and-setasides.md for the structure. v0.1 ships
  # a focused procurement-relevant subset (~25 codes) plus the full
  # first-character category map. Even unknown codes get a sensible
  # `category` from the prefix letter.
  class Psc
    attr_reader :code, :title, :category_code, :category

    def initialize(code:, title:, category_code:, category:)
      @code          = code
      @title         = title
      @category_code = category_code
      @category      = category
      freeze
    end

    def to_h
      { code: code, title: title, category_code: category_code, category: category }
    end

    def ==(other)
      other.is_a?(Psc) && code == other.code
    end
    alias eql? ==

    def hash
      code.hash
    end

    DATA_PATH = File.expand_path("data/psc.json", __dir__)

    class << self
      # Returns the Psc for the given 4-char code, or nil if the code
      # isn't in the shipped table.
      def lookup(code)
        index[code.to_s.upcase]
      end

      # Even unknown codes get a category from the first-character map.
      # Useful when a consumer needs "this is an IT spend" but doesn't
      # need the full title.
      def category_for(code)
        categories[code.to_s[0]&.upcase]
      end

      def all
        @all ||= index.values.freeze
      end

      def categories
        @categories ||= data["categories"].freeze
      end

      private

      def data
        @data ||= JSON.parse(File.read(DATA_PATH))
      end

      def index
        @index ||= build_index
      end

      def build_index
        data["entries"].to_h do |entry|
          code = entry["code"]
          cat_code = code[0]
          [
            code,
            new(
              code: code, title: entry["title"],
              category_code: cat_code, category: categories[cat_code]
            )
          ]
        end.freeze
      end
    end
  end
end
