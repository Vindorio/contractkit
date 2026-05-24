# frozen_string_literal: true

RSpec.describe Contractkit::CrossReference do
  let(:agency) do
    Contractkit::Agency.new(code: "DOD", name: "Department of Defense", cgac: "097")
  end

  let(:opportunity) do
    Contractkit::Opportunity.new(
      notice_id: "n-1", title: "IT mod",
      agency: agency, naics_code: "541512", psc_code: "D316",
      place_of_performance: Contractkit::PlaceOfPerformance.new(state: "VA")
    )
  end

  describe ".awards_for filter construction" do
    it "defaults to agency + NAICS filters with a 5-year lookback window" do
      filters_seen = nil
      fake_search = instance_double(Contractkit::AwardSearch, first: [])
      allow(Contractkit::Award).to receive(:search) do |**kwargs|
        filters_seen = kwargs[:filters]
        fake_search
      end

      described_class.awards_for(opportunity: opportunity)

      expect(filters_seen["agencies"]).to    eq([{ "type" => "awarding", "tier" => "toptier",
                                                   "name" => "Department of Defense" }])
      expect(filters_seen["naics_codes"]).to eq(["541512"])
      expect(filters_seen).not_to have_key("psc_codes") # not in default match
      expect(filters_seen).not_to have_key("place_of_performance_locations")
      expect(filters_seen["time_period"].first["end_date"]).to eq(Date.today.iso8601)
    end

    it "adds psc_codes when :psc is in match" do
      filters_seen = nil
      allow(Contractkit::Award).to receive(:search) do |**kwargs|
        filters_seen = kwargs[:filters]
        instance_double(Contractkit::AwardSearch, first: [])
      end

      described_class.awards_for(opportunity: opportunity, match: %i[agency naics psc])

      expect(filters_seen["psc_codes"]).to eq(["D316"])
    end

    it "adds place_of_performance_locations when :state is in match" do
      filters_seen = nil
      allow(Contractkit::Award).to receive(:search) do |**kwargs|
        filters_seen = kwargs[:filters]
        instance_double(Contractkit::AwardSearch, first: [])
      end

      described_class.awards_for(opportunity: opportunity, match: %i[agency naics state])

      expect(filters_seen["place_of_performance_locations"])
        .to eq([{ "country" => "USA", "state" => "VA" }])
    end
  end

  describe ".likely_incumbent" do
    def award_for(uei, amount)
      Contractkit::Award.new(
        award_id: "a-#{uei}-#{amount}",
        recipient: Contractkit::Recipient.new(name: "Vendor #{uei}", uei: uei),
        obligated_amount: BigDecimal(amount.to_s)
      )
    end

    it "returns the recipient when one entity holds >50% of obligation" do
      awards = [
        award_for("DOM", 7_000_000),
        award_for("OTH", 2_000_000),
        award_for("ETC", 1_000_000)
      ]
      expect(described_class.likely_incumbent(awards).uei).to eq("DOM")
    end

    it "returns nil when no single recipient dominates (multi-award IDIQ)" do
      awards = [
        award_for("A", 3_000_000),
        award_for("B", 3_500_000),
        award_for("C", 3_500_000)
      ]
      expect(described_class.likely_incumbent(awards)).to be_nil
    end

    it "returns nil on an empty award list" do
      expect(described_class.likely_incumbent([])).to be_nil
    end

    it "ignores awards with no recipient (sparse rows)" do
      awards = [
        Contractkit::Award.new(award_id: "x", recipient: nil,
                               obligated_amount: BigDecimal("1000000")),
        award_for("DOM", 9_000_000)
      ]
      expect(described_class.likely_incumbent(awards).uei).to eq("DOM")
    end
  end
end

RSpec.describe Contractkit::Opportunity do
  describe "#related_awards / #likely_incumbent" do
    let(:opp) do
      described_class.new(
        notice_id: "x", title: "t",
        agency: Contractkit::Agency.new(code: "DOD", name: "Department of Defense", cgac: "097"),
        naics_code: "541512"
      )
    end

    it "#related_awards delegates to CrossReference.awards_for" do
      allow(Contractkit::CrossReference).to receive(:awards_for).and_return([])
      opp.related_awards(lookback: 3)
      expect(Contractkit::CrossReference).to have_received(:awards_for)
        .with(opportunity: opp, lookback: 3)
    end

    it "#likely_incumbent delegates through related_awards" do
      allow(Contractkit::CrossReference).to receive_messages(awards_for: [], likely_incumbent: nil)
      opp.likely_incumbent
      expect(Contractkit::CrossReference).to have_received(:awards_for).with(opportunity: opp)
      expect(Contractkit::CrossReference).to have_received(:likely_incumbent).with([])
    end
  end
end
