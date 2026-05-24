# frozen_string_literal: true

RSpec.describe Contractkit::CodedValue do
  describe ".build" do
    it "returns nil when both code and description are blank" do
      expect(described_class.build(code: nil, description: "")).to be_nil
    end

    it "returns a value object when only one side is present" do
      v = described_class.build(code: "A", description: nil)
      expect(v).to be_a(described_class)
      expect(v.code).to eq("A")
      expect(v.description).to be_nil
    end
  end

  describe "value semantics" do
    it "is frozen and value-equal on (code, description)" do
      a = described_class.build(code: "A", description: "Apple")
      b = described_class.build(code: "A", description: "Apple")
      c = described_class.build(code: "A", description: "Apricot")
      expect(a).to be_frozen
      expect(a).to eq(b)
      expect(a).not_to eq(c)
      expect({ a => 1 }[b]).to eq(1)
    end
  end

  describe "#to_h" do
    it "is a flat hash" do
      expect(described_class.build(code: "X", description: "ex").to_h)
        .to eq(code: "X", description: "ex")
    end
  end
end
