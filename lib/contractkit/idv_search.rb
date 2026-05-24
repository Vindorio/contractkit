# frozen_string_literal: true

module Contractkit
  # Result handle for {Contractkit::Idv.search}. Mirrors
  # {Contractkit::AwardSearch}: record-level via Enumerable, batch-level
  # via #each_batch. Always injects IDV_AWARD_TYPE_CODES into the
  # filters — there is no way to ask USASpending for IDVs without that
  # award-type slice.
  class IdvSearch
    include Enumerable

    def initialize(client:, filters:, fields: nil, limit: nil, per_page: nil)
      @client   = client
      @filters  = filters
      @fields   = fields
      @limit    = limit
      @per_page = per_page
    end

    # Yields one Idv at a time across all matching pages.
    def each(&block)
      return enum_for(:each) unless block

      each_batch { |batch| batch.each(&block) }
    end

    # Yields one Array<Idv> per upstream USASpending page.
    def each_batch(&block)
      return enum_for(:each_batch) unless block

      filters = idv_filters(@filters)
      kwargs = { filters: filters }
      kwargs[:fields]   = @fields   if @fields
      kwargs[:limit]    = @limit    if @limit
      kwargs[:per_page] = @per_page if @per_page

      @client.search(**kwargs) do |raw_batch|
        yield Contractkit::Usaspending::ResponseParser.parse_idv_batch(raw_batch)
      end
    end

    private

    def idv_filters(filters)
      out = filters.transform_keys(&:to_s)
      out["award_type_codes"] = Contractkit::Idv::IDV_AWARD_TYPE_CODES.dup
      out
    end
  end
end
