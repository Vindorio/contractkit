# frozen_string_literal: true

RSpec.describe Contractkit::PlaceOfPerformance do
  describe ".from_sam" do
    it "handles the string-state shape" do
      pop = described_class.from_sam(
        "state" => "VA",
        "city" => "Arlington",
        "country" => "USA",
        "zip" => "22202"
      )

      expect(pop.state).to   eq("VA")
      expect(pop.city).to    eq("Arlington")
      expect(pop.country).to eq("USA")
      expect(pop.zip).to     eq("22202")
    end

    it "handles the object-state shape (SAM polymorphism)" do
      pop = described_class.from_sam(
        "state" => { "code" => "VA", "name" => "Virginia" },
        "city" => { "code" => nil, "name" => "Arlington" }
      )

      expect(pop.state).to eq("VA")        # prefers code
      expect(pop.city).to  eq("Arlington") # falls back to name
    end

    it "tolerates a fully nil placeOfPerformance" do
      pop = described_class.from_sam(nil)
      expect(pop.state).to be_nil
      expect(pop.city).to  be_nil
    end

    it "treats empty-string state as nil" do
      pop = described_class.from_sam("state" => "")
      expect(pop.state).to be_nil
    end
  end

  describe ".from_usaspending" do
    it "maps USASpending's flat string keys" do
      pop = described_class.from_usaspending(
        "Place of Performance State Code" => "VA",
        "Place of Performance Country Code" => "USA",
        "Place of Performance Zip5" => "22202"
      )

      expect(pop.state).to   eq("VA")
      expect(pop.country).to eq("USA")
      expect(pop.zip).to     eq("22202")
    end

    it "returns an empty PlaceOfPerformance for a nil input" do
      expect(described_class.from_usaspending(nil).state).to be_nil
    end
  end

  describe "value semantics" do
    it "is frozen" do
      expect(described_class.new(state: "VA")).to be_frozen
    end

    it "equals by hash content" do
      a = described_class.new(state: "VA", city: "Arlington")
      b = described_class.new(state: "VA", city: "Arlington")
      expect(a).to eq(b)
    end
  end
end
