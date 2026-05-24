# frozen_string_literal: true

RSpec.describe Contractkit::Transaction do
  let(:base_mod) do
    {
      "id" => 1,
      "modification_number" => "P00000",
      "action_date" => "2026-01-01",
      "federal_action_obligation" => 1_000_000.00,
      "action_type" => "A",
      "action_type_description" => "ADDITIONAL WORK (NEW AGREEMENT, FUNDING ONLY ACTION)",
      "type" => "C",
      "type_description" => "DELIVERY ORDER",
      "description" => "Base award"
    }
  end

  let(:option_exercise) do
    base_mod.merge(
      "id" => 2,
      "modification_number" => "P00001",
      "action_date" => "2027-01-01",
      "federal_action_obligation" => 250_000.00,
      "action_type" => "B",
      "action_type_description" => "SUPPLEMENTAL AGREEMENT FOR WORK WITHIN SCOPE",
      "description" => "Option year 1"
    )
  end

  let(:ceiling_increase) do
    base_mod.merge(
      "id" => 3,
      "modification_number" => "P00002",
      "action_date" => "2027-06-01",
      "federal_action_obligation" => 500_000.00,
      "action_type" => "C",
      "action_type_description" => "FUNDING ONLY ACTION",
      "description" => "Ceiling raised"
    )
  end

  it "is value-equal by id" do
    a = Contractkit::Usaspending::ResponseParser.parse_transaction(base_mod)
    b = Contractkit::Usaspending::ResponseParser.parse_transaction(base_mod)
    expect(a).to eq(b)
    expect(a).to be_frozen
  end

  describe ".for_award (auto-pagination)" do
    it "concatenates batches into a single array" do
      client = instance_double(Contractkit::Usaspending::Client)
      allow(client).to receive(:transactions).and_yield([base_mod, option_exercise])
                                             .and_yield([ceiling_increase])

      result = described_class.for_award("X", client: client)
      expect(result.size).to eq(3)
      expect(result.map(&:modification_number)).to eq(%w[P00000 P00001 P00002])
    end
  end

  it "sum of federal_action_obligation reconstructs total obligation" do
    txs = [base_mod, option_exercise, ceiling_increase].map do |row|
      Contractkit::Usaspending::ResponseParser.parse_transaction(row)
    end
    total = txs.sum(BigDecimal("0")) { |t| t.federal_action_obligation || 0 }
    expect(total).to eq(BigDecimal("1750000"))
  end

  it "preserves action_type code + description distinctly per mod" do
    a = Contractkit::Usaspending::ResponseParser.parse_transaction(base_mod)
    b = Contractkit::Usaspending::ResponseParser.parse_transaction(option_exercise)
    expect(a.action_type.code).to eq("A")
    expect(b.action_type.code).to eq("B")
    expect(b.action_type.description).to start_with("SUPPLEMENTAL")
  end
end
