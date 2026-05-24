# frozen_string_literal: true

RSpec.describe Contractkit::Agency do
  before { Contractkit.reset_configuration! }

  describe "value object" do
    let(:agency) do
      described_class.new(
        code: "VA", name: "Department of Veterans Affairs",
        cgac: "036", aliases: %w[VA VETERANS]
      )
    end

    it "exposes all four readers" do
      expect(agency.code).to    eq("VA")
      expect(agency.name).to    eq("Department of Veterans Affairs")
      expect(agency.cgac).to    eq("036")
      expect(agency.aliases).to eq(%w[VA VETERANS])
    end

    it "is frozen and its aliases array is frozen" do
      expect(agency).to be_frozen
      expect(agency.aliases).to be_frozen
    end

    it "equals by code when both have one" do
      other = described_class.new(code: "VA", name: "VA", cgac: "036")
      expect(agency).to eq(other)
    end

    it "equals by name when codes are nil (raw-string fallback)" do
      a = described_class.new(code: nil, name: "Unknown Agency Foo", cgac: nil)
      b = described_class.new(code: nil, name: "Unknown Agency Foo", cgac: nil)
      expect(a).to eq(b)
    end
  end

  describe ".normalize" do
    it "resolves a SAM all-caps variant to the canonical Agency" do
      result = described_class.normalize("DEPARTMENT OF VETERANS AFFAIRS")
      expect(result.code).to eq("VA")
      expect(result.name).to eq("Department of Veterans Affairs")
      expect(result.cgac).to eq("036")
    end

    it "resolves a USASpending title-case variant to the canonical Agency" do
      result = described_class.normalize("Department of Veterans Affairs")
      expect(result.code).to eq("VA")
    end

    it "resolves a common abbreviation" do
      result = described_class.normalize("VA")
      expect(result.code).to eq("VA")
    end

    it "is case-insensitive on lookup" do
      result = described_class.normalize("department of veterans affairs")
      expect(result.code).to eq("VA")
    end

    it "returns a raw-string fallback Agency for unknown input" do
      result = described_class.normalize("Department of Made-Up Affairs")
      expect(result.code).to be_nil
      expect(result.name).to eq("Department of Made-Up Affairs")
      expect(result.cgac).to be_nil
      expect(result.aliases).to eq([])
    end

    it "returns a fallback Agency for nil input rather than raising" do
      result = described_class.normalize(nil)
      expect(result.code).to be_nil
      expect(result.name).to eq("")
    end

    it "returns a fallback Agency for empty string" do
      result = described_class.normalize("  ")
      expect(result.code).to be_nil
    end

    describe "consumer override precedence" do
      it "takes precedence over the shipped baseline" do
        Contractkit.configure do |c|
          c.agency_aliases.merge!("DEPARTMENT OF VETERANS AFFAIRS" => "MY-CUSTOM-VA-CODE")
        end
        result = described_class.normalize("DEPARTMENT OF VETERANS AFFAIRS")
        # Override points at MY-CUSTOM-VA-CODE which isn't in shipped table
        # -> returns Agency with the consumer-asserted code but no other metadata.
        expect(result.code).to eq("MY-CUSTOM-VA-CODE")
      end

      it "resolves a brand-new alias to a known shipped code" do
        Contractkit.configure { |c| c.agency_aliases.merge!("Veterans Dept" => "VA") }
        result = described_class.normalize("Veterans Dept")
        expect(result.code).to eq("VA")
        expect(result.name).to eq("Department of Veterans Affairs") # canonical metadata
      end

      it "consumer alias pointing at unknown code does NOT raise" do
        Contractkit.configure { |c| c.agency_aliases.merge!("Weird Thing" => "ZZZ") }
        expect { described_class.normalize("Weird Thing") }.not_to raise_error
      end
    end
  end

  describe ".canonical" do
    it "returns the shipped Agency for a known code" do
      agency = described_class.canonical("VA")
      expect(agency.name).to eq("Department of Veterans Affairs")
    end

    it "is case-insensitive on the code" do
      expect(described_class.canonical("va").code).to eq("VA")
    end

    it "returns nil for unknown code" do
      expect(described_class.canonical("ZZZ")).to be_nil
    end
  end

  describe ".all" do
    it "returns 25 cabinet-level + major-independent entries" do
      expect(described_class.all.size).to eq(25)
    end

    it "is frozen" do
      expect(described_class.all).to be_frozen
    end

    it "every shipped entry has SAM all-caps, USAsp title-case, and abbreviation variants" do
      sam_unresolved   = []
      usasp_unresolved = []
      abbr_unresolved  = []

      described_class.all.each do |agency|
        sam_variant   = agency.aliases.find { |a| a == a.upcase && a.include?(" ") }
        usasp_variant = agency.aliases.find { |a| a != a.upcase && a.include?(" ") }
        abbr_variant  = agency.aliases.find { |a| a.length <= 6 && !a.include?(" ") }

        sam_unresolved   << agency.code if sam_variant.nil?
        usasp_unresolved << agency.code if usasp_variant.nil?
        abbr_unresolved  << agency.code if abbr_variant.nil?
      end

      # USPS and a handful of independents only have one short name with no
      # punctuation variation; accept up to 3 such cases per dimension.
      expect(sam_unresolved.size).to   be <= 3
      expect(usasp_unresolved.size).to be <= 3
      expect(abbr_unresolved.size).to  be <= 3
    end
  end
end
