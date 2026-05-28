# frozen_string_literal: true

require "json"
require "bigdecimal"

RSpec.describe Contractkit::Fpds::ResponseParser do
  def load_fixture
    JSON.parse(File.read(File.expand_path(
                           "../../fixtures/live_responses/fpds_contract.json", __dir__
                         )))
  end

  let(:fixture) { load_fixture }
  let(:award_hash) { fixture["awardSummary"].first }
  let(:award) { described_class.parse(award_hash) }

  describe ".parse" do
    it "maps contract identity from contractId" do
      expect(award.piid).to eq("SPE3SU25F97V0")
      expect(award.parent_piid).to eq("SPE30023DSA78")
      expect(award.award_id).to eq("SPE3SU25F97V0-0")
    end

    it "maps award type from coreData.awardOrIDVType" do
      expect(award.award_type).to eq("DELIVERY ORDER")
      expect(award.contract_award_type.code).to eq("C")
      expect(award.contract_award_type.description).to eq("DELIVERY ORDER")
    end

    it "maps dollar amounts from awardDetails.dollars" do
      expect(award.obligated_amount).to eq(BigDecimal("202.39"))
      expect(award.base_and_all_options_value).to eq(BigDecimal("202.39"))
      expect(award.base_and_exercised_options_value).to eq(BigDecimal("202.39"))
      expect(award.ceiling).to eq(BigDecimal("202.39"))
      expect(award.total_obligation).to eq(BigDecimal("202.39"))
    end

    it "maps awarding agency from federalOrganization.contractingInformation" do
      expect(award.awarding_agency).not_to be_nil
      expect(award.awarding_agency.name).to match(/Department of Defense/i)
      expect(award.awarding_subagency_name).to eq("DEFENSE LOGISTICS AGENCY")
    end

    it "maps funding agency from federalOrganization.fundingInformation" do
      expect(award.funding_agency).not_to be_nil
      expect(award.funding_agency.name).to match(/Department of Defense/i)
    end

    it "maps NAICS from productOrServiceInformation.principalNaics" do
      expect(award.naics_code).to eq("311812")
    end

    it "maps PSC from productOrServiceInformation.productOrService" do
      expect(award.psc_code).to eq("8915")
    end

    it "maps competition fields from competitionInformation" do
      expect(award.extent_competed.code).to eq("A")
      expect(award.extent_competed.description).to eq("FULL AND OPEN COMPETITION")
      expect(award.solicitation_procedures.code).to eq("NP")
      expect(award.solicitation_procedures.description).to eq("NEGOTIATED PROPOSAL/QUOTE")
      expect(award.number_of_offers_received).to eq(1)
    end

    it "maps contract pricing from acquisitionData" do
      expect(award.type_of_contract_pricing.code).to eq("J")
      expect(award.type_of_contract_pricing.description).to eq("FIRM FIXED PRICE")
    end

    it "maps period from awardDetails.dates" do
      expect(award.period).not_to be_nil
      expect(award.period.start_date).to eq(Date.parse("2025-02-20"))
      expect(award.period.end_date).to eq(Date.parse("2025-02-20"))
    end

    it "maps place of performance from principalPlaceOfPerformance" do
      expect(award.place_of_performance).not_to be_nil
      expect(award.place_of_performance.state).to eq("IL")
      expect(award.place_of_performance.city).to eq("MORTON")
      expect(award.place_of_performance.country).to eq("USA")
      expect(award.place_of_performance.zip).to eq("615509058")
    end

    it "maps recipient from awardeeData" do
      expect(award.recipient).not_to be_nil
      expect(award.recipient.name).to eq("VERMILION VALLEY PRODUCE, INC.")
      expect(award.recipient.uei).to eq("HKK3H54PK7C3")
    end

    it "maps description from productOrServiceInformation" do
      expect(award.description).to eq("4567323815!SALAD MIX, CHL,")
    end

    it "maps last_modified_at from transactionData" do
      expect(award.last_modified_at).to eq("2025-06-11T07:18:02Z")
    end

    it "preserves the raw hash" do
      expect(award.raw).to eq(award_hash)
    end
  end

  describe ".parse_batch" do
    it "parses multiple awards" do
      batch = fixture["awardSummary"]
      awards = described_class.parse_batch(batch)
      expect(awards.size).to eq(1)
      expect(awards.first).to be_a(Contractkit::Award)
    end
  end

  describe "edge cases" do
    it "handles missing sections gracefully" do
      sparse = {
        "contractId" => { "piid" => "TEST001", "modificationNumber" => "0" }
      }
      result = described_class.parse(sparse)
      expect(result.piid).to eq("TEST001")
      expect(result.award_id).to eq("TEST001-0")
      expect(result.obligated_amount).to be_nil
      expect(result.naics_code).to be_nil
    end

    it "handles empty awardSummary array" do
      expect(described_class.parse_batch([])).to eq([])
    end
  end
end
