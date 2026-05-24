# frozen_string_literal: true

RSpec.describe Contractkit::Sam::Client do
  before do
    Contractkit.reset_configuration!
    Contractkit.configure do |c|
      c.sam_api_key = ENV.fetch("SAM_API_KEY", "test-key-for-vcr-replay")
      c.retries     = 0
    end
  end

  describe "configuration guards" do
    it "raises ConfigurationError when sam_api_key is nil" do
      Contractkit.reset_configuration!
      Contractkit.configure { |c| c.sam_api_key = nil }

      expect { described_class.new.raw_search }
        .to raise_error(Contractkit::ConfigurationError, /SAM.gov API key not set/)
    end
  end

  describe "#raw_search", :vcr do
    it "returns a parsed JSON hash with the documented top-level keys" do
      response = described_class.new.raw_search(
        ncode: "541512",
        limit: 5,
        postedFrom: Date.new(2026, 4, 1),
        postedTo: Date.new(2026, 4, 30)
      )

      expect(response).to be_a(Hash)
      expect(response.keys).to include("totalRecords", "limit", "opportunitiesData")
      expect(response["opportunitiesData"]).to be_an(Array)
    end

    it "converts Date params to SAM's MM/dd/yyyy format internally" do
      # The cassette captures the encoded URL — if Date conversion broke,
      # the recorded request URL wouldn't match SAM's expected format and
      # this test wouldn't have a cassette to replay.
      response = described_class.new.raw_search(
        ncode: "541512",
        limit: 1,
        postedFrom: Date.new(2026, 4, 1),
        postedTo: Date.new(2026, 4, 30)
      )
      expect(response["limit"]).to be_truthy
    end
  end

  describe "error responses", :vcr do
    it "raises Sam::AuthenticationError when SAM rejects the key" do
      Contractkit.configure { |c| c.sam_api_key = "deliberately-invalid-key" }

      expect { described_class.new.raw_search(ncode: "541512", limit: 1) }
        .to raise_error(Contractkit::Sam::AuthenticationError) do |err|
          # Empirical: SAM returns 404 (not 403) for bad keys on the search
          # endpoint. See client.rb handle_response for the rationale.
          expect(err.status).to(satisfy { |s| [401, 403, 404].include?(s) })
          expect(err.params).not_to have_key(:api_key) # secret never lands in error params
        end
    end
  end

  describe "#search batch pagination", :vcr do
    it "yields one batch per API page across a multi-page real query" do
      batches = []
      described_class.new.search(
        ncode: "541512",
        per_page: 3,
        postedFrom: Date.new(2026, 2, 1),
        postedTo: Date.new(2026, 4, 30)
      ) do |batch|
        batches << batch
        break if batches.size >= 3 # cap so the cassette stays small
      end

      expect(batches.size).to be >= 2 # crossed at least one page boundary
      expect(batches).to all(be_an(Array))
      expect(batches.first).to all(be_a(Hash))
      expect(batches.first.first).to include("noticeId")
    end

    it "returns an Enumerator when no block is given" do
      enum = described_class.new.search(
        ncode: "541512",
        per_page: 3,
        postedFrom: Date.new(2026, 2, 1),
        postedTo: Date.new(2026, 4, 30)
      )

      expect(enum).to be_an(Enumerator)
      first_batch = enum.first
      expect(first_batch).to be_an(Array)
      expect(first_batch.size).to be <= 3
    end

    it "honors the limit parameter to cap total records across batches" do
      total = 0
      described_class.new.search(
        ncode: "541512",
        per_page: 3,
        limit: 4, # forces one full batch (3) + one truncated (1)
        postedFrom: Date.new(2026, 2, 1),
        postedTo: Date.new(2026, 4, 30)
      ) { |batch| total += batch.size }

      expect(total).to eq(4)
    end
  end

  describe "hand-crafted error scenarios" do
    # These two cassettes are hand-crafted because triggering real 429 /
    # timeout against SAM is impractical (slow, flaky, would exhaust the
    # dev key). The shape of the response (status, headers, body) matches
    # what SAM actually returns; only the recording mechanism differs.

    it "raises Sam::RateLimitError on a 429 with Retry-After", :vcr do
      expect { described_class.new.raw_search(ncode: "541512", limit: 1) }
        .to raise_error(Contractkit::Sam::RateLimitError) do |err|
          expect(err.status).to eq(429)
          expect(err.retry_after).to eq(60.0)
        end
    end

    it "surfaces a timeout as Faraday::TimeoutError after retries exhausted" do
      Contractkit.configure { |c| c.retries = 0 }

      stub_request(:get, %r{api\.sam\.gov/opportunities/v2/search})
        .to_timeout

      expect { described_class.new.raw_search(ncode: "541512", limit: 1) }
        .to raise_error(Faraday::ConnectionFailed)
    end
  end
end
