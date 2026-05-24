# frozen_string_literal: true

RSpec.describe Contractkit::Opportunity do
  before do
    Contractkit.reset_configuration!
    Contractkit.configure do |c|
      c.sam_api_key = ENV.fetch("SAM_API_KEY", "test-key-for-vcr-replay")
      c.retries = 0
    end
  end

  describe ".search", :vcr do
    it "yields individual Opportunity objects via .each (record-level)" do
      results = described_class.search(
        ncode: "541512",
        per_page: 3,
        postedFrom: Date.new(2026, 2, 1),
        postedTo: Date.new(2026, 4, 30)
      ).first(5)

      expect(results).to all(be_a(described_class))
      expect(results.first.notice_id).to be_a(String)
      expect(results.first.agency).to    be_a(Contractkit::Agency)
    end

    it "yields batches of Opportunity objects via #each_batch" do
      batches = []
      described_class.search(
        ncode: "541512",
        per_page: 3,
        postedFrom: Date.new(2026, 2, 1),
        postedTo: Date.new(2026, 4, 30)
      ).each_batch do |batch|
        batches << batch
        break if batches.size >= 2
      end

      expect(batches).to all(be_an(Array))
      expect(batches.first).to all(be_a(described_class))
    end
  end

  describe ".search with multiple NAICS values" do
    it "issues sequential requests and merges results (SAM ncode is single-value)" do
      # No VCR — we stub the underlying client to verify call shape.
      fake_client = instance_double(Contractkit::Sam::Client)
      params_seen = []

      allow(fake_client).to receive(:search) do |**params, &block|
        params_seen << params.slice(:ncode)
        block.call([{ "noticeId" => "x-#{params[:ncode]}", "title" => "t" }])
      end

      described_class.search(client: fake_client, naics: %w[541512 541511]).to_a

      expect(params_seen).to eq([{ ncode: "541512" }, { ncode: "541511" }])
    end
  end

  describe ".find", :vcr do
    it "raises NotFoundError when no opportunity matches the noticeId" do
      expect { described_class.find("definitely-not-a-real-notice-id-xyz") }
        .to raise_error(Contractkit::NotFoundError, /no SAM opportunity found/)
    end
  end

  describe ".modified_since", :vcr do
    it "fires the block per-Opportunity" do
      yielded = []
      # Date window matches the M1 batch-pagination cassette so we can
      # replay without hitting SAM during routine test runs.
      described_class.modified_since(
        Date.new(2026, 2, 1),
        ncode: "541512", per_page: 3, postedTo: Date.new(2026, 4, 30)
      ) do |opp|
        yielded << opp
        break if yielded.size >= 3
      end

      expect(yielded).to all(be_a(described_class))
    end

    it "returns an OpportunitySearch when no block given" do
      result = described_class.modified_since(
        Date.new(2026, 4, 1),
        ncode: "541512", postedTo: Date.new(2026, 4, 30)
      )
      expect(result).to be_a(Contractkit::OpportunitySearch)
    end
  end
end
