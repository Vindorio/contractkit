# frozen_string_literal: true

RSpec.describe Contractkit::Usaspending::ResponseParser do
  let(:full_award) do
    {
      "Award ID" => "FA877126C0042",
      "parent_award_piid" => "FA877126D0001",
      "Contract Award Type" => "DEFINITIVE CONTRACT",
      "Award Amount" => 4_250_000.00,
      "Base + All Options Value" => 12_500_000.00,
      "Recipient Name" => "BOOZ ALLEN HAMILTON INC.",
      "Recipient UEI" => "ABC123XYZ456",
      "Recipient DUNS" => "987654321",
      "recipient_id" => "r-abc",
      "Awarding Agency" => "Department of Defense",
      "Awarding Sub Agency" => "Department of the Air Force",
      "Funding Agency" => "Department of Defense",
      "NAICS" => "541512",
      "PSC" => "D316",
      "Type of Set Aside" => "8A",
      "Start Date" => "2026-03-15",
      "End Date" => "2031-03-14",
      "Last Modified Date" => "2026-04-01",
      "Description" => "IT modernization services",
      "Place of Performance State Code" => "VA",
      "Place of Performance Country Code" => "USA",
      "Place of Performance Zip5" => "22202"
    }
  end

  describe ".parse on a full award" do
    let(:award) { described_class.parse(full_award) }

    it "returns a frozen Award instance" do
      expect(award).to be_a(Contractkit::Award)
      expect(award).to be_frozen
    end

    it "carries the scalar fields" do
      expect(award.award_id).to    eq("FA877126C0042")
      expect(award.piid).to        eq("FA877126C0042")
      expect(award.parent_piid).to eq("FA877126D0001")
      expect(award.award_type).to  eq("DEFINITIVE CONTRACT")
      expect(award.naics_code).to  eq("541512")
      expect(award.psc_code).to    eq("D316")
    end

    it "money fields are BigDecimal (cent-precision)" do
      expect(award.obligated_amount).to eq(BigDecimal("4250000.00"))
      expect(award.ceiling).to          eq(BigDecimal("12500000.00"))
      # Headline obligation < ceiling — distinction preserved
      expect(award.obligated_amount).to be < award.ceiling
    end

    it "constructs a Recipient with UEI and DUNS" do
      expect(award.recipient).to be_a(Contractkit::Recipient)
      expect(award.recipient.name).to eq("BOOZ ALLEN HAMILTON INC.")
      expect(award.recipient.uei).to  eq("ABC123XYZ456")
      expect(award.recipient.duns).to eq("987654321")
    end

    it "normalizes the awarding agency to a canonical Contractkit::Agency" do
      expect(award.awarding_agency).to be_a(Contractkit::Agency)
      expect(award.awarding_agency.code).to eq("DOD")
    end

    it "constructs a Period with Date (not DateTime)" do
      expect(award.period.start_date).to be_a(Date)
      expect(award.period.end_date).to   be_a(Date)
      expect(award.period.start_date).to eq(Date.new(2026, 3, 15))
      expect(award.period.end_date).to   eq(Date.new(2031, 3, 14))
    end

    it "normalizes the set-aside to symbol + raw code" do
      expect(award.set_aside_code).to eq("8A")
      expect(award.set_aside).to      eq(:sba_8a)
    end

    it "builds place_of_performance from USASpending's flat keys" do
      expect(award.place_of_performance).to be_a(Contractkit::PlaceOfPerformance)
      expect(award.place_of_performance.state).to eq("VA")
      expect(award.place_of_performance.zip).to   eq("22202")
    end

    it "preserves .raw" do
      expect(award.raw).to be(full_award)
    end
  end

  describe "missing optional fields" do
    it "tolerates a sparse award without raising" do
      award = described_class.parse(
        "Award ID" => "minimal-1",
        "Recipient Name" => nil,
        "Award Amount" => nil
      )

      expect(award.award_id).to        eq("minimal-1")
      expect(award.recipient).to       be_nil
      expect(award.obligated_amount).to be_nil
      expect(award.period.start_date).to be_nil
    end
  end

  describe "agency unknown fallback" do
    it "returns a raw-string Agency when the input isn't in the alias table" do
      award = described_class.parse(
        full_award.merge("Awarding Agency" => "AGENCY OF MADE-UP STUFF")
      )
      expect(award.awarding_agency.code).to be_nil
      expect(award.awarding_agency.name).to eq("AGENCY OF MADE-UP STUFF")
    end
  end

  describe "money normalization edge cases" do
    it "accepts a numeric string" do
      award = described_class.parse(full_award.merge("Award Amount" => "1234567.89"))
      expect(award.obligated_amount).to eq(BigDecimal("1234567.89"))
    end

    it "falls back to nil for garbage" do
      award = described_class.parse(full_award.merge("Award Amount" => "n/a"))
      expect(award.obligated_amount).to be_nil
    end
  end

  describe ".parse_batch" do
    it "maps an array of award hashes to Award objects" do
      result = described_class.parse_batch([full_award, full_award.merge("Award ID" => "b")])
      expect(result.size).to eq(2)
      expect(result).to all(be_a(Contractkit::Award))
    end
  end
end
