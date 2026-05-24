# frozen_string_literal: true

require "json"

module Contractkit
  # Set-aside normalization. SAM's raw codes ("SBA", "8A", "WOSBSS",
  # "SDVOSBC", etc.) are the source of truth; the gem maps each to a
  # stable Ruby symbol for ergonomics and a human-readable label.
  #
  # See docs/domain/naics-and-setasides.md for the program-by-program
  # explanation of what each set-aside means.
  module SetAside
    DATA_PATH = File.expand_path("data/set_aside_codes.json", __dir__)

    class UnknownCode < Contractkit::Error
      def initialize(raw)
        super("unknown set-aside input: #{raw.inspect}")
      end
    end

    class << self
      # Resolve a SAM code, USASpending code, or human-string variant to
      # a stable Ruby symbol. Empty/nil input -> :none (full and open).
      # Unknown -> Contractkit::SetAside::UnknownCode (a subclass of
      # Contractkit::Error, NOT ArgumentError).
      def normalize(input)
        return :none if input.nil? || input.to_s.strip.empty?

        key = input.to_s.strip
        symbol = index[key] || index[key.upcase] || index[key.downcase]
        raise UnknownCode, input if symbol.nil?

        symbol
      end

      # Same as normalize, but returns :unknown rather than raising when
      # the input doesn't match any known code/alias. Parsers use this so
      # one unrecognized set-aside doesn't blow up an entire opportunity
      # record; raising remains the right call when consumers reach for
      # normalize directly.
      def safe_normalize(input)
        normalize(input)
      rescue UnknownCode
        :unknown
      end

      # Canonical human-readable label for a symbol. Returns nil for
      # unknown symbols (rather than raising — callers ask "do we know
      # this?" via #known?).
      def label(symbol)
        entry_by_symbol[symbol]&.fetch(:label)
      end

      # Canonical SAM code for a symbol. Inverse of normalize for the
      # canonical (non-alias) lookup.
      def code(symbol)
        entry_by_symbol[symbol]&.fetch(:code)
      end

      def known?(symbol)
        entry_by_symbol.key?(symbol)
      end

      # Every known symbol, frozen.
      def all
        @all ||= entry_by_symbol.keys.freeze
      end

      private

      def data
        @data ||= JSON.parse(File.read(DATA_PATH))
      end

      def entry_by_symbol
        @entry_by_symbol ||= data["entries"].to_h do |e|
          [
            e["symbol"].to_sym,
            { code: e["code"], symbol: e["symbol"].to_sym, label: e["label"] }
          ]
        end.freeze
      end

      # Maps every recognized input (code + aliases) -> symbol.
      def index
        @index ||= build_index
      end

      def build_index
        idx = {}
        data["entries"].each do |entry|
          symbol = entry["symbol"].to_sym
          ([entry["code"]] + (entry["aliases"] || [])).each do |variant|
            next if variant.to_s.empty?

            idx[variant] = symbol
            idx[variant.upcase] = symbol
            idx[variant.downcase] = symbol
          end
        end
        idx.freeze
      end
    end
  end
end
