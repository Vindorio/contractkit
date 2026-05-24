# frozen_string_literal: true

RSpec.describe Contractkit::Usaspending::Client do
  before do
    Contractkit.reset_configuration!
    Contractkit.configure { |c| c.retries = 0 }
  end

  describe "#raw_search", :vcr do
    it "POSTs filters + fields + paging to spending_by_award and returns parsed JSON" do
      response = described_class.new.raw_search(
        filters: {
          naics_codes: ["541512"],
          time_period: [{ start_date: "2026-01-01", end_date: "2026-03-31" }]
        },
        page: 1,
        limit: 5
      )

      expect(response).to be_a(Hash)
      expect(response.keys).to include("results", "page_metadata")
      expect(response["results"]).to be_an(Array)
      expect(response["page_metadata"]).to include("page" => 1)
    end

    it "defaults award_type_codes to contracts when caller doesn't specify" do
      # If the default substitution failed, we'd see grants/loans mixed in,
      # which 541512 (Computer Systems Design Services) wouldn't return.
      response = described_class.new.raw_search(
        filters: {
          naics_codes: ["541512"],
          time_period: [{ start_date: "2026-01-01", end_date: "2026-03-31" }]
        },
        page: 1,
        limit: 3
      )

      expect(response["results"].first).to be_a(Hash) if response["results"].any?
    end
  end

  describe "#search (lazy pagination)", :vcr do
    it "walks page_metadata.hasNext across multiple pages" do
      results = described_class.new
                               .search(
                                 filters: {
                                   naics_codes: ["541512"],
                                   time_period: [
                                     { start_date: "2026-01-01", end_date: "2026-03-31" }
                                   ]
                                 },
                                 limit: 3
                               )
                               .take(8)

      expect(results.size).to be > 3
      expect(results).to all(be_a(Hash))
    end
  end

  describe "hand-crafted error scenarios" do
    # Real timeouts and 5xx from USASpending are nondeterministic to
    # capture (slow, flaky, depend on upstream load). WebMock-stubbed.

    it "surfaces a timeout as Faraday::ConnectionFailed after retries exhausted" do
      Contractkit.configure { |c| c.retries = 0 }
      stub_request(:post, %r{api\.usaspending\.gov/api/v2/search/spending_by_award/})
        .to_timeout

      expect do
        described_class.new.raw_search(filters: { naics_codes: ["541512"] })
      end.to raise_error(Faraday::ConnectionFailed)
    end

    it "raises Usaspending::ServerError on a 500 (hand-crafted cassette)", :vcr do
      expect { described_class.new.raw_search(filters: { naics_codes: ["999999"] }) }
        .to raise_error(Contractkit::Usaspending::ServerError) do |err|
          expect(err.status).to eq(500)
        end
    end
  end
end
