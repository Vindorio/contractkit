# frozen_string_literal: true

require "json"

# Parser verification against real USASpending v2 responses captured
# live on 2026-05-24. These specs are the ground-truth check that the
# M4 FIXMEs were resolved: they exercise parse_detail / parse_idv /
# parse_transaction / parse_subaward against the actual JSON the API
# returns, not a synthesized fixture.
#
# If USASpending ever changes a field name, one of these specs will
# fail and the failure will name the field — re-record the JSON under
# spec/fixtures/live_responses/ and adjust the parser.
RSpec.describe "USASpending parser — live response shapes" do
  def load_fixture(name)
    JSON.parse(File.read(File.expand_path(
                           "../../fixtures/live_responses/#{name}.json", __dir__
                         )))
  end

  describe "parse_detail (definitive contract)" do
    let(:hash) { load_fixture("usp_award_detail") }
    let(:award) { Contractkit::Usaspending::ResponseParser.parse_detail(hash) }

    it "maps the three-tier pricing from top-level keys" do
      expect(award.total_obligation).to eq(BigDecimal("41772.06"))
      expect(award.base_and_exercised_options_value).to eq(BigDecimal("41772.06"))
      expect(award.base_and_all_options_value).to eq(BigDecimal("41772.06"))
      expect(award.ceiling).to eq(BigDecimal("41772.06"))
      # No upstream total_contract_value key — fall back to base_and_all_options.
      expect(award.total_contract_value).to eq(BigDecimal("41772.06"))
    end

    it "extracts competition fields from latest_transaction_contract_data" do
      expect(award.number_of_offers_received).to eq(1)
      expect(award.extent_competed.code).to eq("G")
      expect(award.extent_competed.description).to eq("NOT COMPETED UNDER SAP")
      expect(award.type_of_contract_pricing.code).to eq("J")
      expect(award.type_of_contract_pricing.description).to eq("FIRM FIXED PRICE")
      expect(award.solicitation_procedures.code).to eq("SP1")
    end

    it "maps contract identity + agency from the detail shape" do
      expect(award.award_id).to eq("CONT_AWD_ZL01_9700_H9224015A0001_9700")
      expect(award.piid).to eq("ZL01")
      expect(award.contract_award_type.code).to eq("A")
      expect(award.contract_award_type.description).to eq("BPA CALL")
      expect(award.awarding_agency&.name).to match(/Department of Defense/i)
    end
  end

  describe "parse_idv" do
    let(:hash) { load_fixture("usp_idv_detail") }
    let(:idv)  { Contractkit::Usaspending::ResponseParser.parse_idv(hash) }

    it "reads idv_type from top-level `type` key" do
      expect(idv.idv_type.code).to eq("IDV_C")
      expect(idv.idv_type.description).to eq("FSS")
    end

    it "captures multiple_or_single_award_description from latest_transaction_contract_data" do
      expect(idv.multiple_or_single_award_description).to eq("MULTIPLE AWARD")
    end

    it "leaves last_date_to_order nil when upstream has no value, exposes period_end_date" do
      # This FSS IDV has no Last Date To Order and a null
      # potential_end_date. last_date_to_order stays nil rather than
      # silently aliasing period_end_date — the recompete helper
      # falls back to period_end_date explicitly so callers can tell
      # signal sources apart.
      expect(idv.last_date_to_order).to be_nil
      expect(idv.period_end_date).to eq(Date.parse("2027-05-14"))
    end

    it "parses awarding agency from nested toptier_agency.name" do
      expect(idv.awarding_agency&.name).to match(/Veterans Affairs/i)
    end
  end

  describe "parse_transaction" do
    let(:hash)  { load_fixture("usp_transactions") }
    let(:txns)  { Contractkit::Usaspending::ResponseParser.parse_transactions(hash["results"]) }

    it "parses every field in the live response shape" do # rubocop:disable RSpec/MultipleExpectations
      expect(txns.size).to eq(2)
      mod, base = txns

      expect(mod.id).to eq("CONT_TX_9700_9700_ZL01_1_H9224015A0001_0")
      expect(mod.modification_number).to eq("1")
      expect(mod.action_date).to eq(Date.parse("2025-02-18"))
      expect(mod.federal_action_obligation).to eq(BigDecimal("-421.94"))
      expect(mod.action_type.code).to eq("M")
      expect(mod.action_type.description).to eq("OTHER ADMINISTRATIVE ACTION")

      expect(base.modification_number).to eq("0")
      expect(base.federal_action_obligation).to eq(BigDecimal("42194"))
      expect(base.action_type).to be_nil # base award has no action_type
    end
  end

  describe "parse_subaward (per-award endpoint shape)" do
    let(:hash) { load_fixture("usp_subawards") }
    let(:subs) { Contractkit::Usaspending::ResponseParser.parse_subawards(hash["results"]) }

    it "parses the sparse per-award response (id, subaward_number, recipient_name, amount)" do
      expect(subs).not_to be_empty
      first = subs.first
      expect(first.subaward_number).to be_a(String)
      expect(first.amount).to be_a(BigDecimal)
      expect(first.sub_recipient_name).to be_a(String)
      # UEI fields aren't returned by /api/v2/subawards/ — confirm they're nil.
      expect(first.sub_recipient_uei).to be_nil
      expect(first.prime_recipient_uei).to be_nil
    end
  end

  describe "USASpending IDV search field shape" do
    it "returns 'Last Date To Order' in the search response (often null)" do
      hash = load_fixture("usp_idv_search")
      expect(hash["results"].first.keys).to include("Last Date To Order")
    end
  end
end
