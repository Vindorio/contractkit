# frozen_string_literal: true

require "json"

module Contractkit
  # Canonical agency value object. See docs/design/data-models.md and
  # docs/domain/agency-normalization.md for the design rationale.
  #
  # Four fields: code, name, cgac, aliases. Frozen after construction —
  # treat as a value, not an entity.
  #
  # Resolution is three-layered (consumer overrides → shipped table →
  # raw-string fallback). Never raises, never returns nil from .normalize.
  class Agency
    attr_reader :code, :name, :cgac, :aliases

    def initialize(code:, name:, cgac:, aliases: [])
      @code    = code
      @name    = name
      @cgac    = cgac
      @aliases = aliases.dup.freeze
      freeze
    end

    # @return [Hash] flat hash form of all four fields (for serialization).
    def to_h
      { code: code, name: name, cgac: cgac, aliases: aliases }
    end

    # Equality by code when both have one (canonical identity); otherwise
    # by name. Two raw-string fallback Agencies with the same name are
    # equal even though both have nil codes.
    def ==(other)
      return false unless other.is_a?(Agency)
      return code == other.code if code && other.code

      name == other.name
    end
    alias eql? ==

    # @return [Integer] hash code matching the equality contract.
    def hash
      [code, name].hash
    end

    # Path to the shipped agency-aliases JSON (see {Contractkit::Agency.all}).
    DATA_PATH = File.expand_path("data/agency_aliases.json", __dir__)

    class << self
      # Returns a canonical Agency for the given input string, resolving
      # in priority order:
      #   1. Consumer-registered aliases (Contractkit.configuration.agency_aliases)
      #   2. Shipped baseline table (DATA_PATH)
      #   3. Raw-string fallback (code: nil, name: <input>)
      #
      # Never raises, never returns nil.
      def normalize(input, config: Contractkit.configuration)
        return fallback(nil) if input.nil?

        text = input.to_s
        return fallback(text) if text.strip.empty?

        if (code_from_overrides = config.agency_aliases[text])
          return canonical(code_from_overrides) || fallback_with_code(text, code_from_overrides)
        end

        baseline_index[text] || fallback(text)
      end

      # Returns the shipped canonical Agency for a code (e.g. "VA"), or nil
      # if the code isn't in the shipped table.
      def canonical(code)
        baseline_by_code[code.to_s.upcase]
      end

      # Frozen array of every shipped canonical Agency. Consumers can use
      # this to seed their own reference tables.
      def all
        baseline.dup.freeze
      end

      private

      def baseline
        @baseline ||= load_baseline
      end

      def load_baseline
        JSON.parse(File.read(DATA_PATH)).map do |entry|
          new(
            code: entry.fetch("code"),
            name: entry.fetch("name"),
            cgac: entry.fetch("cgac"),
            aliases: entry.fetch("aliases", [])
          )
        end.freeze
      end

      def baseline_by_code
        @baseline_by_code ||= baseline.to_h { |a| [a.code, a] }.freeze
      end

      # Index every alias (and the canonical name itself) → Agency. Used
      # for the layer-2 lookup. Case-insensitive on the input.
      def baseline_index
        @baseline_index ||= build_index
      end

      def build_index
        index = {}
        baseline.each do |agency|
          ([agency.name] + agency.aliases).each do |key|
            index[key] = agency
            index[key.downcase] = agency
          end
        end
        index.freeze
      end

      def fallback(raw)
        new(code: nil, name: raw.to_s, cgac: nil, aliases: [])
      end

      # When a consumer-registered alias points at a code we don't ship,
      # we still produce an Agency with the consumer-asserted code so
      # downstream code can store / query by it.
      def fallback_with_code(raw, code)
        new(code: code, name: raw, cgac: nil, aliases: [])
      end
    end
  end
end
