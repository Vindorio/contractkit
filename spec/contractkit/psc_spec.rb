# frozen_string_literal: true

RSpec.describe Contractkit::Psc do
  describe ".lookup" do
    it "returns a Psc for a known 4-char code" do
      psc = described_class.lookup("D316")
      expect(psc).not_to be_nil
      expect(psc.title).to         eq("IT and Telecom - Cybersecurity")
      expect(psc.category_code).to eq("D")
      expect(psc.category).to      eq("IT and Telecom")
    end

    it "is case-insensitive on the code" do
      expect(described_class.lookup("d316").code).to eq("D316")
    end

    it "returns nil for an unknown code" do
      expect(described_class.lookup("ZZZZ")).to be_nil
    end

    it "covers entries from multiple major prefix categories" do
      expect(described_class.lookup("A111")).not_to be_nil # R&D
      expect(described_class.lookup("D302")).not_to be_nil # IT
      expect(described_class.lookup("R425")).not_to be_nil # Professional services
      expect(described_class.lookup("Q201")).not_to be_nil # Medical
      expect(described_class.lookup("V211")).not_to be_nil # Transportation
    end
  end

  describe ".category_for" do
    it "returns the category for a known prefix letter even on an unshipped code" do
      expect(described_class.category_for("D9999")).to eq("IT and Telecom")
      expect(described_class.category_for("A123")).to  eq("R&D")
      expect(described_class.category_for("Y0AB"))
        .to eq("Construction of Structures and Facilities")
    end

    it "returns nil for unknown prefix" do
      expect(described_class.category_for("9999")).to be_nil
    end
  end

  describe "value semantics" do
    let(:psc) { described_class.lookup("D316") }

    it "is frozen" do
      expect(psc).to be_frozen
    end

    it "equals by code" do
      expect(psc).to eq(described_class.lookup("D316"))
    end
  end
end
