# frozen_string_literal: true

RSpec.describe Contractkit::Usaspending::ResponseParser do
  describe ".parse with M4 expanded pricing on search-row (#36)" do
    let(:row_with_pricing) do
      {
        "Award ID" => "GS35F0119Y0001",
        "Award Amount" => 1_250_000.00,
        "Base + All Options Value" => 5_000_000.00,
        "Base + Exercised Options Value" => 2_000_000.00,
        "Total Contract Value" => 5_000_000.00,
        "Total Obligation" => 1_250_000.00,
        "Recipient Name" => "ACME CORP",
        "Recipient UEI" => "UEI12345",
        "NAICS" => "541512",
        "Awarding Agency" => "Department of Defense",
        "Start Date" => "2026-01-01",
        "End Date" => "2031-01-01"
      }
    end

    it "exposes the three-tier pricing fields as BigDecimal" do
      a = described_class.parse(row_with_pricing)
      expect(a.obligated_amount).to eq(BigDecimal("1250000"))
      expect(a.base_and_exercised_options_value).to eq(BigDecimal("2000000"))
      expect(a.base_and_all_options_value).to eq(BigDecimal("5000000"))
      expect(a.total_contract_value).to eq(BigDecimal("5000000"))
      expect(a.total_obligation).to eq(BigDecimal("1250000"))
    end

    it "leaves competition fields nil on the search-row path (detail-only)" do
      a = described_class.parse(row_with_pricing)
      expect(a.number_of_offers_received).to be_nil
      expect(a.extent_competed).to be_nil
      expect(a.type_of_contract_pricing).to be_nil
    end

    it "satisfies the obligated <= exercised <= total invariant" do
      a = described_class.parse(row_with_pricing)
      expect(a.obligated_amount).to be <= a.base_and_exercised_options_value
      expect(a.base_and_exercised_options_value).to be <= a.base_and_all_options_value
    end
  end

  describe ".parse_detail (single-award /api/v2/awards/{id}/)" do
    let(:detail) do
      {
        "generated_unique_award_id" => "CONT_AWD_FA877126C0042_9700",
        "piid" => "FA877126C0042",
        "type" => "C",
        "type_description" => "DELIVERY ORDER",
        "category" => "contract",
        "total_obligation" => "4250000",
        "base_and_all_options" => "12500000",
        "base_exercised_options" => "8000000",
        "total_contract_value" => "12500000",
        "description" => "IT services",
        "period_of_performance" => {
          "start_date" => "2026-03-15",
          "end_date" => "2031-03-14"
        },
        "awarding_agency" => {
          "toptier_agency" => { "name" => "Department of Defense" },
          "subtier_agency" => { "name" => "Department of the Air Force" }
        },
        "funding_agency" => {
          "toptier_agency" => { "name" => "Department of Defense" }
        },
        "recipient" => {
          "recipient_name" => "BOOZ ALLEN HAMILTON INC.",
          "recipient_uei" => "ABC123XYZ456"
        },
        "place_of_performance" => {
          "state_code" => "VA",
          "country_code" => "USA",
          "zip5" => "22202"
        },
        "latest_transaction_contract_data" => {
          "naics" => "541512",
          "product_or_service_code" => "D316",
          "type_set_aside" => "8A",
          "number_of_offers_received" => "3",
          "extent_competed" => "A",
          "extent_competed_description" => "FULL AND OPEN COMPETITION",
          "type_of_contract_pricing" => "J",
          "type_of_contract_pric_desc" => "FIRM FIXED PRICE",
          "solicitation_procedures" => "NP",
          "solicitation_procedures_description" => "NEGOTIATED PROPOSAL/QUOTE"
        }
      }
    end

    it "populates competition fields as CodedValue" do
      a = described_class.parse_detail(detail)
      expect(a.extent_competed).to be_a(Contractkit::CodedValue)
      expect(a.extent_competed.code).to eq("A")
      expect(a.extent_competed.description).to eq("FULL AND OPEN COMPETITION")
      expect(a.type_of_contract_pricing.code).to eq("J")
      expect(a.solicitation_procedures.description).to eq("NEGOTIATED PROPOSAL/QUOTE")
    end

    it "parses number_of_offers_received as Integer" do
      a = described_class.parse_detail(detail)
      expect(a.number_of_offers_received).to eq(3)
    end

    it "populates all three pricing tiers as BigDecimal" do
      a = described_class.parse_detail(detail)
      expect(a.obligated_amount).to eq(BigDecimal("4250000"))
      expect(a.base_and_exercised_options_value).to eq(BigDecimal("8000000"))
      expect(a.base_and_all_options_value).to eq(BigDecimal("12500000"))
      expect(a.total_contract_value).to eq(BigDecimal("12500000"))
    end

    it "constructs Recipient and nested Agency from detail shape" do
      a = described_class.parse_detail(detail)
      expect(a.recipient.uei).to eq("ABC123XYZ456")
      expect(a.awarding_agency.name).to match(/Defense/i).or eq("DOD")
      expect(a.awarding_subagency_name).to eq("Department of the Air Force")
    end

    it "tolerates a sparse detail (partial fields)" do
      sparse = { "generated_unique_award_id" => "x", "piid" => "P1" }
      a = described_class.parse_detail(sparse)
      expect(a.award_id).to eq("x")
      expect(a.extent_competed).to be_nil
      expect(a.obligated_amount).to be_nil
    end
  end

  describe ".parse_idv (#37)" do
    let(:row) do
      {
        "Award ID" => "47QTCA21D000X",
        "generated_unique_award_id" => "CONT_IDV_47QTCA21D000X_4730",
        "Start Date" => "2026-01-01",
        "Last Date To Order" => "2027-06-30",
        "End Date" => "2031-01-01",
        "idv_type" => "B",
        "idv_type_description" => "INDEFINITE DELIVERY CONTRACT",
        "child_award_count" => 12,
        "child_award_total_obligation" => 4_200_000.00,
        "Recipient Name" => "ACME CORP",
        "Recipient UEI" => "UEI12345",
        "NAICS" => "541512",
        "Awarding Agency" => "Department of Defense"
      }
    end

    it "returns a frozen Idv with parsed dates" do
      idv = described_class.parse_idv(row)
      expect(idv).to be_a(Contractkit::Idv)
      expect(idv).to be_frozen
      expect(idv.last_date_to_order).to eq(Date.new(2027, 6, 30))
      expect(idv.period_start_date).to eq(Date.new(2026, 1, 1))
    end

    it "exposes idv_type as CodedValue" do
      idv = described_class.parse_idv(row)
      expect(idv.idv_type.code).to eq("B")
      expect(idv.idv_type.description).to match(/INDEFINITE DELIVERY/)
    end

    it "carries child rollups as Integer + BigDecimal" do
      idv = described_class.parse_idv(row)
      expect(idv.child_award_count).to eq(12)
      expect(idv.child_award_total_obligation).to eq(BigDecimal("4200000"))
    end
  end

  describe ".parse_transaction (#38)" do
    let(:row) do
      {
        "id" => 998_877,
        "modification_number" => "P00003",
        "action_date" => "2027-03-15",
        "federal_action_obligation" => 250_000.00,
        "action_type" => "B",
        "action_type_description" => "SUPPLEMENTAL AGREEMENT FOR WORK WITHIN SCOPE",
        "type" => "C",
        "type_description" => "DELIVERY ORDER",
        "description" => "Option year 2 exercise"
      }
    end

    it "parses dates, money, and CodedValue pairs" do
      t = described_class.parse_transaction(row)
      expect(t).to be_a(Contractkit::Transaction)
      expect(t.action_date).to eq(Date.new(2027, 3, 15))
      expect(t.federal_action_obligation).to eq(BigDecimal("250000"))
      expect(t.action_type.code).to eq("B")
      expect(t.action_type.description).to start_with("SUPPLEMENTAL")
      expect(t.type.description).to eq("DELIVERY ORDER")
    end

    it "preserves raw" do
      t = described_class.parse_transaction(row)
      expect(t.raw).to be(row)
    end
  end

  describe ".parse_subaward (#40)" do
    let(:row) do
      {
        "internal_id" => "sub-abc-1",
        "Sub-Award ID" => "SUB001",
        "Sub-Award Date" => "2027-02-01",
        "Sub-Award Amount" => 125_000.00,
        "Sub-Award Description" => "Cloud infra carve-out",
        "Prime Award ID" => "FA877126C0042",
        "prime_award_generated_internal_id" => "CONT_AWD_FA877126C0042_9700",
        "Prime Recipient UEI" => "PRIMEUEI001",
        "Prime Recipient Name" => "ACME CORP",
        "Sub-Recipient UEI" => "SUBUEI002",
        "Sub-Recipient Name" => "SUBCO LLC",
        "Sub-Recipient City" => "Reston",
        "Sub-Recipient State" => "VA",
        "Sub-Recipient Country" => "USA",
        "NAICS" => "541512"
      }
    end

    it "parses both sides of the prime/sub pair" do
      s = described_class.parse_subaward(row)
      expect(s.prime_recipient_uei).to eq("PRIMEUEI001")
      expect(s.sub_recipient_uei).to eq("SUBUEI002")
      expect(s.amount).to eq(BigDecimal("125000"))
      expect(s.action_date).to eq(Date.new(2027, 2, 1))
      expect(s.sub_recipient_address).to eq(city: "Reston", state: "VA", country: "USA")
    end
  end
end
