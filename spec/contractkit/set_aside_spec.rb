# frozen_string_literal: true

RSpec.describe Contractkit::SetAside do
  describe ".normalize" do
    it "resolves a SAM code to a symbol" do
      expect(described_class.normalize("SBA")).to     eq(:small_business)
      expect(described_class.normalize("8A")).to      eq(:sba_8a)
      expect(described_class.normalize("WOSB")).to    eq(:wosb)
      expect(described_class.normalize("HZC")).to     eq(:hubzone_sole_source)
      expect(described_class.normalize("SDVOSBS")).to eq(:sdvosb)
    end

    it "resolves human-readable variants (USASpending style)" do
      expect(described_class.normalize("Service-Disabled Veteran-Owned Small Business"))
        .to eq(:sdvosb)
      expect(described_class.normalize("Total Small Business Set-Aside"))
        .to eq(:small_business)
      expect(described_class.normalize("Full and Open"))
        .to eq(:none)
    end

    it "is case-insensitive" do
      expect(described_class.normalize("sba")).to eq(:small_business)
      expect(described_class.normalize("Sba")).to eq(:small_business)
    end

    it "returns :none for nil or empty input" do
      expect(described_class.normalize(nil)).to  eq(:none)
      expect(described_class.normalize("")).to   eq(:none)
      expect(described_class.normalize("   ")).to eq(:none)
    end

    it "raises Contractkit::Error (not ArgumentError) for unknown input" do
      expect { described_class.normalize("FAKEFAKE") }
        .to raise_error(Contractkit::SetAside::UnknownCode)

      expect { described_class.normalize("FAKEFAKE") }
        .to raise_error(Contractkit::Error) # parent class
    end
  end

  describe ".label" do
    it "returns the canonical human string for known symbols" do
      expect(described_class.label(:small_business)).to eq("Small Business Set-Aside")
      expect(described_class.label(:sba_8a)).to         eq("8(a) Set-Aside")
      expect(described_class.label(:hubzone_sole_source)).to eq("HUBZone Sole Source")
      expect(described_class.label(:none)).to eq("Full and Open")
    end

    it "returns nil for unknown symbols" do
      expect(described_class.label(:not_a_real_thing)).to be_nil
    end
  end

  describe ".code" do
    it "returns the canonical SAM code for a known symbol" do
      expect(described_class.code(:small_business)).to    eq("SBA")
      expect(described_class.code(:sba_8a)).to            eq("8A")
      expect(described_class.code(:hubzone_sole_source)).to eq("HZC")
    end
  end

  describe ".known? / .all" do
    it ".known? returns true for shipped symbols, false otherwise" do
      expect(described_class.known?(:small_business)).to be(true)
      expect(described_class.known?(:not_a_real_thing)).to be(false)
    end

    it ".all returns the frozen array of every known symbol" do
      expect(described_class.all).to include(:small_business, :sba_8a, :wosb, :none)
      expect(described_class.all).to be_frozen
    end
  end

  describe "round-trip" do
    it "normalize(code(symbol)) == symbol for every known entry" do
      described_class.all.each do |symbol|
        next if symbol == :none # NONE code -> normalize(nil) -> :none round-trip is special

        expect(described_class.normalize(described_class.code(symbol))).to eq(symbol)
      end
    end
  end
end
