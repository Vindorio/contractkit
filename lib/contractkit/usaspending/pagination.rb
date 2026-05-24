# frozen_string_literal: true

module Contractkit
  module Usaspending
    module Pagination
      # Page-based lazy Enumerable over USASpending's spending_by_award.
      # Stops when page_metadata.hasNext is false.
      #
      # Per docs/domain/usaspending.md, queries past page=1000 (~100k
      # records) can time out before responding. Consumers doing bulk
      # pulls should window by date or agency to keep page counts shallow.
      class Page
        include Enumerable

        def initialize(client:, filters:, fields:, limit: 100)
          @client  = client
          @filters = filters
          @fields  = fields
          @limit   = limit
        end

        def each(&block)
          return enum_for(:each) unless block_given?

          page = 1
          loop do
            response = @client.raw_search(
              filters: @filters, fields: @fields, page: page, limit: @limit
            )
            results = response["results"] || []
            results.each(&block)

            break unless response.dig("page_metadata", "hasNext")

            page += 1
          end
        end
      end
    end
  end
end
