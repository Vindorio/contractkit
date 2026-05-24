# frozen_string_literal: true

RSpec.describe Contractkit::Award do
  before do
    Contractkit.reset_configuration!
    Contractkit.configure { |c| c.retries = 0 }
  end

  describe ".search", :vcr do
    it "yields individual Award objects via .each (record-level)" do
      results = described_class.search(
        filters: {
          naics_codes: ["541512"],
          time_period: [{ start_date: "2026-01-01", end_date: "2026-03-31" }]
        },
        per_page: 3
      ).first(5)

      expect(results).to all(be_a(described_class))
      expect(results.first.award_id).to be_a(String)
      expect(results.first.obligated_amount).to be_a(BigDecimal)
    end

    it "yields batches via #each_batch" do
      batches = []
      described_class.search(
        filters: {
          naics_codes: ["541512"],
          time_period: [{ start_date: "2026-01-01", end_date: "2026-03-31" }]
        },
        per_page: 3
      ).each_batch do |batch|
        batches << batch
        break if batches.size >= 2
      end

      expect(batches).to all(be_an(Array))
      expect(batches.first).to all(be_a(described_class))
    end
  end

  describe ".updated_since", :vcr do
    it "wraps search with a time_period filter (action_date proxy)" do
      enum = described_class.updated_since(
        Date.new(2026, 1, 1),
        filters: { naics_codes: ["541512"] }, per_page: 3
      )

      expect(enum).to be_a(Contractkit::AwardSearch)
      first = enum.first(3)
      expect(first).to all(be_a(described_class))
    end
  end

  describe ".find (deferred to v0.2)" do
    it "raises NotImplementedError with a clear forward-pointer message" do
      expect { described_class.find("any-id") }
        .to raise_error(NotImplementedError, /v0\.2/)
    end
  end
end

RSpec.describe Contractkit::Recipient do
  before { Contractkit.reset_configuration! }

  describe ".find" do
    it "constructs a Recipient from the raw_recipient response" do
      fake_client = instance_double(Contractkit::Usaspending::Client)
      allow(fake_client).to receive(:raw_recipient).with("ABC123XYZ456").and_return(
        "name" => "BOOZ ALLEN HAMILTON INC.",
        "uei" => "ABC123XYZ456",
        "duns" => "987654321",
        "recipient_id" => "r-abc"
      )

      recipient = described_class.find("ABC123XYZ456", client: fake_client)
      expect(recipient).to be_a(described_class)
      expect(recipient.name).to eq("BOOZ ALLEN HAMILTON INC.")
      expect(recipient.uei).to  eq("ABC123XYZ456")
      expect(recipient.duns).to eq("987654321")
    end
  end
end
