# frozen_string_literal: true

module Contractkit
  # Result handle for {Contractkit::Award.search}. Wraps Usaspending::
  # Client#search and presents both record-level (`include Enumerable`)
  # and batch-level (`#each_batch`) surfaces.
  #
  # Mirrors {Contractkit::OpportunitySearch} for consistency — same
  # mental model on both upstream APIs.
  class AwardSearch
    include Enumerable

    def initialize(client:, filters:, fields: nil, limit: nil, per_page: nil)
      @client   = client
      @filters  = filters
      @fields   = fields
      @limit    = limit
      @per_page = per_page
    end

    def each(&block)
      return enum_for(:each) unless block

      each_batch { |batch| batch.each(&block) }
    end

    def each_batch(&block)
      return enum_for(:each_batch) unless block

      kwargs = { filters: @filters }
      kwargs[:fields]   = @fields   if @fields
      kwargs[:limit]    = @limit    if @limit
      kwargs[:per_page] = @per_page if @per_page

      @client.search(**kwargs) do |raw_batch|
        yield(Contractkit::Usaspending::ResponseParser.parse_batch(raw_batch))
      end
    end
  end
end
