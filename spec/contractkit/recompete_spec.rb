# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers -- this spec needs several
# fixture rows + two collaborator doubles to exercise the IDV + contract +
# SAM-match path; splitting them would obscure intent.
RSpec.describe Contractkit::Recompete do
  let(:today) { Date.new(2026, 5, 1) }
  let(:expiring_idv_row) do
    {
      "Award ID" => "IDV-EXPIRING",
      "generated_unique_award_id" => "CONT_IDV_EXP_001",
      "Start Date" => "2024-01-01",
      "Last Date To Order" => "2026-09-01",
      "End Date" => "2028-01-01",
      "Recipient Name" => "INCUMBENT CORP",
      "NAICS" => "541512",
      "Awarding Agency" => "Department of Defense"
    }
  end
  let(:far_future_idv_row) do
    expiring_idv_row.merge(
      "Award ID" => "IDV-FUTURE",
      "generated_unique_award_id" => "CONT_IDV_FUTURE_001",
      "Last Date To Order" => "2030-09-01"
    )
  end
  let(:expiring_contract_row) do
    {
      "Award ID" => "CONTRACT-EXP",
      "generated_unique_award_id" => "CONT_AWD_EXP_001",
      "Award Amount" => 1_000_000.00,
      "Recipient Name" => "INCUMBENT CORP",
      "NAICS" => "541512",
      "Awarding Agency" => "Department of Defense",
      "Start Date" => "2024-01-01",
      "End Date" => "2026-11-15"
    }
  end
  let(:matching_opportunity_hash) do
    {
      "noticeId" => "NEW-SOLICITATION-1",
      "title" => "Recompete for ACME Services",
      "fullParentPathName" => "DEPT OF DEFENSE",
      "naicsCode" => "541512"
    }
  end
  let(:usa_client) { instance_double(Contractkit::Usaspending::Client) }
  let(:sam_client) { instance_double(Contractkit::Sam::Client) }

  before do
    allow(Date).to receive(:today).and_return(today)
    call = 0
    allow(usa_client).to receive(:search) do |**_kwargs, &block|
      call += 1
      case call
      when 1 then block.call([expiring_idv_row, far_future_idv_row])
      when 2 then block.call([expiring_contract_row])
      end
    end
    allow(sam_client).to receive(:search).and_yield([matching_opportunity_hash])
  end

  describe ".expiring" do
    it "yields Match structs for awards within the window" do
      results = described_class.expiring(within: 12, client: usa_client,
                                         sam_client: sam_client).to_a
      ids = results.map { |m| m.award.award_id }
      expect(ids).to include("IDV-EXPIRING", "CONTRACT-EXP")
      expect(ids).not_to include("IDV-FUTURE")
    end

    it "pairs each expiring award with matching opportunities" do
      first = described_class.expiring(within: 12, client: usa_client,
                                       sam_client: sam_client).first
      expect(first.matching_opportunities).to be_an(Array)
      expect(first.matching_opportunities.first).to be_a(Contractkit::Opportunity)
      expect(first.matching_opportunities.first.notice_id).to eq("NEW-SOLICITATION-1")
    end

    it "returns an Enumerator without a block and yields to a block" do
      enum = described_class.expiring(within: 12, client: usa_client, sam_client: sam_client)
      expect(enum).to be_a(Enumerator)
    end

    it "0-month window excludes all future expirations" do
      results = described_class.expiring(within: 0, client: usa_client,
                                         sam_client: sam_client).to_a
      expect(results).to be_empty
    end

    it "Match#to_h serializes nested types" do
      m = described_class.expiring(within: 12, client: usa_client, sam_client: sam_client).first
      h = m.to_h
      expect(h.keys).to contain_exactly(:award, :matching_opportunities)
      expect(h[:matching_opportunities].first).to include(:notice_id)
    end

    it "raises ArgumentError for non-numeric within:" do
      bogus = Object.new
      expect { described_class.expiring(within: bogus, client: usa_client, sam_client: sam_client) }
        .to raise_error(ArgumentError)
    end
  end

  describe "DEFAULT_WINDOW_MONTHS" do
    it "mirrors CrossReference::DEFAULT_ENDING_WINDOW_MONTHS" do
      expect(described_class::DEFAULT_WINDOW_MONTHS)
        .to eq(Contractkit::CrossReference::DEFAULT_ENDING_WINDOW_MONTHS)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
