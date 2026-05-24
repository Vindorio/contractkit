# frozen_string_literal: true

RSpec.describe Contractkit::Naics do
  describe ".lookup" do
    it "returns the Naics for a known 6-digit code" do
      naics = described_class.lookup("541512")
      expect(naics).not_to be_nil
      expect(naics.title).to eq("Computer Systems Design Services")
    end

    it "carries sector and subsector metadata" do
      naics = described_class.lookup("541512")
      expect(naics.sector_code).to     eq("54")
      expect(naics.sector_title).to    eq("Professional, Scientific, and Technical Services")
      expect(naics.subsector_code).to  eq("541")
      expect(naics.subsector_title).to eq("Professional, Scientific, and Technical Services")
    end

    it "returns nil for an unknown code" do
      expect(described_class.lookup("999999")).to be_nil
    end

    it "accepts integer codes by coercion" do
      expect(described_class.lookup(541_512)).not_to be_nil
    end
  end

  describe "#sector / #subsector chains" do
    let(:naics) { described_class.lookup("541512") }

    it "#sector returns a Naics value object for the 2-digit parent" do
      sector = naics.sector
      expect(sector).to be_a(described_class)
      expect(sector.code).to  eq("54")
      expect(sector.title).to eq("Professional, Scientific, and Technical Services")
    end

    it "#subsector returns a Naics value object for the 3-digit parent" do
      sub = naics.subsector
      expect(sub).to be_a(described_class)
      expect(sub.code).to  eq("541")
      expect(sub.title).to eq("Professional, Scientific, and Technical Services")
    end
  end

  describe "value semantics" do
    it "is frozen" do
      expect(described_class.lookup("541512")).to be_frozen
    end

    it "equals by code (two lookups return value-equal instances)" do
      a = described_class.lookup("541512")
      b = described_class.lookup("541512")
      expect(a).to eq(b)
    end
  end

  describe ".all" do
    it "returns the full shipped subset (≥30 entries for v0.1)" do
      expect(described_class.all.size).to be >= 30
    end

    it "is frozen" do
      expect(described_class.all).to be_frozen
    end
  end
end
