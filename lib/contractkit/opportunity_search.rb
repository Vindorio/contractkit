# frozen_string_literal: true

module Contractkit
  # Result handle for {Contractkit::Opportunity.search}. Wraps the
  # batch-yielding Sam::Client#search underneath but presents two surfaces:
  #
  # - record-level (`include Enumerable`, so `.each` / `.first` / `.take`
  #   yield individual Opportunity objects)
  # - batch-level (`.each_batch` yields arrays of Opportunity matching the
  #   upstream page size, for bulk pipelines)
  #
  # Multi-NAICS handling: SAM only accepts one `ncode` per request. When
  # the caller passes `naics: ["x", "y", "z"]`, this object issues
  # sequential requests and yields the merged result, transparently.
  class OpportunitySearch
    include Enumerable

    def initialize(client:, params:)
      @client = client
      @params = params
    end

    # Yields one Opportunity at a time across all matching pages.
    # @yieldparam opportunity [Contractkit::Opportunity]
    # @return [Enumerator] when no block given
    def each(&block)
      return enum_for(:each) unless block

      each_batch { |batch| batch.each(&block) }
    end

    # Yields one Array<Opportunity> per upstream SAM page. Batch size
    # matches the upstream's natural per-page cap (1000 by default).
    # @yieldparam batch [Array<Contractkit::Opportunity>]
    # @return [Enumerator] when no block given
    def each_batch
      return enum_for(:each_batch) unless block_given?

      ncodes_for_iteration.each do |ncode|
        params = ncode ? @params.merge(ncode: ncode) : @params
        @client.search(**params) do |raw_batch|
          yield Contractkit::Sam::ResponseParser.parse_batch(raw_batch)
        end
      end
    end

    private

    # Returns [nil] when the caller passed no NAICS — one iteration over
    # @params as-is. Otherwise returns the array of NAICS values; the
    # caller's `naics:` (or `ncode:`) array becomes N sequential queries
    # because SAM caps `ncode` to a single value.
    def ncodes_for_iteration
      raw = @params[:naics] || @params[:ncode]
      return [nil] if raw.nil?
      return Array(raw) if raw.is_a?(Array)

      [raw]
    end
  end
end
