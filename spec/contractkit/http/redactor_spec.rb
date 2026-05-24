# frozen_string_literal: true

RSpec.describe Contractkit::Http::Redactor do
  describe ".scrub" do
    it "strips a SAM api_key query param mid-URL" do
      url = "https://api.sam.gov/opportunities/v2/search?ncode=541512&api_key=SAM-abc-123&limit=10"
      expect(described_class.scrub(url))
        .to eq("https://api.sam.gov/opportunities/v2/search?ncode=541512&api_key=[REDACTED]&limit=10")
    end

    it "strips a SAM api_key query param at end of URL" do
      url = "https://api.sam.gov/opportunities/v2/search?api_key=SAM-abc"
      expect(described_class.scrub(url))
        .to eq("https://api.sam.gov/opportunities/v2/search?api_key=[REDACTED]")
    end

    it "leaves the rest of the line intact" do
      log_line = "GET https://api.sam.gov/?api_key=SAM-secret status=200 dur=120ms"
      scrubbed = described_class.scrub(log_line)
      expect(scrubbed).to include("status=200")
      expect(scrubbed).to include("[REDACTED]")
      expect(scrubbed).not_to include("SAM-secret")
    end

    it "is a no-op when the input has no api_key" do
      line = "GET https://api.usaspending.gov/api/v2/search/spending_by_award/"
      expect(described_class.scrub(line)).to eq(line)
    end
  end
end
