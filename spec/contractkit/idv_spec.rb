# frozen_string_literal: true

RSpec.describe Contractkit::Idv do
  let(:idv_row) do
    {
      "Award ID" => "47QTCA21D000X",
      "generated_unique_award_id" => "CONT_IDV_47QTCA21D000X_4730",
      "Start Date" => "2026-01-01",
      "Last Date To Order" => "2027-06-30",
      "End Date" => "2031-01-01",
      "idv_type" => "B",
      "idv_type_description" => "INDEFINITE DELIVERY CONTRACT",
      "Recipient Name" => "ACME CORP",
      "Recipient UEI" => "UEI12345",
      "NAICS" => "541512",
      "Awarding Agency" => "Department of Defense"
    }
  end

  it "is a frozen value object equal by award_id" do
    a = Contractkit::Usaspending::ResponseParser.parse_idv(idv_row)
    b = Contractkit::Usaspending::ResponseParser.parse_idv(idv_row)
    expect(a).to be_frozen
    expect(a).to eq(b)
    expect(a.hash).to eq(b.hash)
  end

  it "exposes IDV_AWARD_TYPE_CODES constant" do
    expect(described_class::IDV_AWARD_TYPE_CODES).to include("IDV_A", "IDV_B", "IDV_E")
  end

  describe ".search injects IDV award types" do
    it "passes IDV codes to the underlying client" do
      client = instance_double(Contractkit::Usaspending::Client)
      received_filters = nil

      allow(client).to receive(:search) do |filters:, **|
        received_filters = filters
        []
      end

      described_class.search(client: client, filters: {}, limit: 5).each_batch { |_| nil }
      expect(received_filters["award_type_codes"]).to eq(described_class::IDV_AWARD_TYPE_CODES)
    end
  end

  it "to_h serializes nested CodedValue and dates" do
    idv = Contractkit::Usaspending::ResponseParser.parse_idv(idv_row)
    h = idv.to_h
    expect(h[:idv_type]).to eq(code: "B", description: "INDEFINITE DELIVERY CONTRACT")
    expect(h[:last_date_to_order]).to eq(Date.new(2027, 6, 30))
  end
end
