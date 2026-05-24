# frozen_string_literal: true

RSpec.describe Contractkit::Subaward do
  let(:prime_sub) do
    {
      "internal_id" => "s1",
      "Sub-Award ID" => "SUB001",
      "Sub-Award Date" => "2027-02-01",
      "Sub-Award Amount" => 125_000.00,
      "Prime Award ID" => "FA877126C0042",
      "Prime Recipient UEI" => "PRIMEUEI001",
      "Prime Recipient Name" => "ACME CORP",
      "Sub-Recipient UEI" => "SUBUEI002",
      "Sub-Recipient Name" => "SUBCO LLC"
    }
  end

  let(:other_sub) do
    prime_sub.merge(
      "internal_id" => "s2",
      "Sub-Award ID" => "SUB002",
      "Sub-Recipient UEI" => "SUBUEI003",
      "Sub-Recipient Name" => "OTHERSUB INC"
    )
  end

  describe ".for_award" do
    it "returns all subaward rows for a prime, across pages" do
      client = instance_double(Contractkit::Usaspending::Client)
      received_filters = nil
      allow(client).to receive(:subawards) do |filters:, **, &block|
        received_filters = filters
        block.call([prime_sub, other_sub])
      end

      result = described_class.for_award("FA877126C0042", client: client)
      expect(result.size).to eq(2)
      expect(result.map(&:sub_recipient_uei)).to include("SUBUEI002", "SUBUEI003")
      expect(received_filters).to include("award_id" => "FA877126C0042")
    end

    it "returns empty array when no subawards (FFATA edge case)" do
      client = instance_double(Contractkit::Usaspending::Client)
      allow(client).to receive(:subawards) # never yields
      result = described_class.for_award("small_award", client: client)
      expect(result).to eq([])
    end
  end

  it "is frozen, value-equal by id" do
    a = Contractkit::Usaspending::ResponseParser.parse_subaward(prime_sub)
    b = Contractkit::Usaspending::ResponseParser.parse_subaward(prime_sub)
    expect(a).to be_frozen
    expect(a).to eq(b)
  end

  it "to_h carries both prime and sub identifiers" do
    s = Contractkit::Usaspending::ResponseParser.parse_subaward(prime_sub)
    h = s.to_h
    expect(h[:prime_recipient_uei]).to eq("PRIMEUEI001")
    expect(h[:sub_recipient_uei]).to eq("SUBUEI002")
    expect(h[:amount]).to eq(BigDecimal("125000"))
  end
end
