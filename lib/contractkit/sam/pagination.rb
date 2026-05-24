# frozen_string_literal: true

module Contractkit
  module Sam
    module Pagination
      # Offset/limit lazy Enumerable over SAM's /opportunities/v2/search.
      #
      # Fetches pages on demand as the caller consumes them — `.first`,
      # `.take(n)`, and early `break` from `.each` only fetch as much as
      # needed. Stops when SAM returns an empty opportunitiesData array
      # OR when totalRecords is reached.
      #
      # Per docs/domain/sam-gov.md, deep-offset queries (>9k) slow down
      # noticeably; consumers doing bulk pulls should partition by date
      # window rather than rely on one giant offset walk.
      class Offset
        include Enumerable

        def initialize(client:, params:, per_page: 100)
          @client   = client
          @params   = params
          @per_page = per_page
        end

        def each(&block)
          return enum_for(:each) unless block_given?

          offset = 0
          loop do
            page = @client.raw_search(**@params, limit: @per_page, offset: offset)
            opportunities = page["opportunitiesData"] || []
            break if opportunities.empty?

            opportunities.each(&block)

            offset += opportunities.size
            total = page["totalRecords"]
            break if total && offset >= total
          end
        end
      end
    end
  end
end
