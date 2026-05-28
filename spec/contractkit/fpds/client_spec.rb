# frozen_string_literal: true

RSpec.describe Contractkit::Fpds::Client do
  let(:sample_response) do
    {
      "awardSummary" => [
        {
          "contractId" => { "piid" => "SPE3SU25F97V0", "modificationNumber" => "0" },
          "coreData" => {
            "awardOrIDVType" => { "code" => "C", "name" => "DELIVERY ORDER" }
          }
        }
      ],
      "totalRecords" => "100",
      "limit" => "1",
      "offset" => "0"
    }
  end

  before do
    Contractkit.reset_configuration!
    Contractkit.configure do |c|
      c.sam_api_key = "test-key"
      c.retries = 0
    end
  end

  describe "#raw_search" do
    it "GETs search params to contract-awards/v1/search and returns parsed JSON" do
      stub_request(:get, %r{api\.sam\.gov/contract-awards/v1/search})
        .with(query: hash_including("api_key" => "test-key"))
        .to_return(status: 200, body: sample_response.to_json,
                   headers: { "Content-Type" => "application/json" })

      response = described_class.new.raw_search(
        contractingDepartmentCode: "9700",
        lastModifiedDate: ["01/01/2025", "12/31/2025"],
        limit: 1
      )

      expect(response).to be_a(Hash)
      expect(response.keys).to include("awardSummary", "totalRecords")
      expect(response["awardSummary"]).to be_an(Array)
      expect(response["totalRecords"]).to eq("100")
    end

    it "converts snake_case filter keys to camelCase" do
      stub_request(:get, %r{api\.sam\.gov/contract-awards/v1/search})
        .with(query: hash_including(
          "contractingDepartmentCode" => "9700",
          "naicsCode" => "541512"
        ))
        .to_return(status: 200, body: sample_response.to_json,
                   headers: { "Content-Type" => "application/json" })

      response = described_class.new.raw_search(
        contracting_department_code: "9700",
        naics_code: "541512",
        limit: 1
      )

      expect(response).to be_a(Hash)
      expect(response["awardSummary"]).to be_an(Array)
    end
  end

  describe "#search batch pagination" do
    let(:page1) do
      {
        "awardSummary" => [{ "contractId" => { "piid" => "A1" } },
                           { "contractId" => { "piid" => "A2" } },
                           { "contractId" => { "piid" => "A3" } }],
        "totalRecords" => "7",
        "limit" => "3",
        "offset" => "0"
      }
    end

    let(:page2) do
      {
        "awardSummary" => [{ "contractId" => { "piid" => "A4" } },
                           { "contractId" => { "piid" => "A5" } },
                           { "contractId" => { "piid" => "A6" } }],
        "totalRecords" => "7",
        "limit" => "3",
        "offset" => "3"
      }
    end

    let(:page3) do
      {
        "awardSummary" => [{ "contractId" => { "piid" => "A7" } }],
        "totalRecords" => "7",
        "limit" => "3",
        "offset" => "6"
      }
    end

    before do
      stub_request(:get, %r{api\.sam\.gov/contract-awards/v1/search})
        .with(query: hash_including("offset" => "0"))
        .to_return(status: 200, body: page1.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, %r{api\.sam\.gov/contract-awards/v1/search})
        .with(query: hash_including("offset" => "3"))
        .to_return(status: 200, body: page2.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, %r{api\.sam\.gov/contract-awards/v1/search})
        .with(query: hash_including("offset" => "6"))
        .to_return(status: 200, body: page3.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    it "yields one batch per API page (block form)" do
      batches = []
      described_class.new.search(
        { contractingDepartmentCode: "9700" },
        per_page: 3
      ) do |batch|
        batches << batch
        break if batches.size >= 2
      end

      expect(batches.size).to eq(2)
      expect(batches).to all(be_an(Array))
    end

    it "returns an Enumerator when no block given" do
      enum = described_class.new.search(
        { contractingDepartmentCode: "9700" },
        per_page: 3
      )

      expect(enum).to be_an(Enumerator)
    end

    it "honors limit to cap total records" do
      total = 0
      described_class.new.search(
        { contractingDepartmentCode: "9700" },
        per_page: 3,
        limit: 5
      ) { |batch| total += batch.size }

      expect(total).to eq(5)
    end
  end

  describe "error scenarios" do
    it "raises Fpds::AuthenticationError when SAM key is invalid" do
      stub_request(:get, %r{api\.sam\.gov/contract-awards/v1/search})
        .with(query: hash_including("api_key" => "test-key"))
        .to_return(status: 403, body: '{"error":"Unauthorized"}')

      expect do
        described_class.new.raw_search(contractingDepartmentCode: "9700", limit: 1)
      end.to raise_error(Contractkit::Fpds::AuthenticationError)
    end

    it "raises Fpds::ServerError on a 500" do
      stub_request(:get, %r{api\.sam\.gov/contract-awards/v1/search})
        .to_return(status: 500, body: '{"error":"Internal Server Error"}')

      expect do
        described_class.new.raw_search(contractingDepartmentCode: "9700", limit: 1)
      end.to raise_error(Contractkit::Fpds::ServerError) do |err|
        expect(err.status).to eq(500)
      end
    end

    it "429s raise Sam::RateLimitError (rate-limiter middleware handles per-host)" do
      stub_request(:get, %r{api\.sam\.gov/contract-awards/v1/search})
        .to_return(status: 429,
                   headers: { "Retry-After" => "60" },
                   body: '{"error":"Rate limit exceeded"}')

      expect do
        described_class.new.raw_search(contractingDepartmentCode: "9700", limit: 1)
      end.to raise_error(Contractkit::Sam::RateLimitError)
    end

    it "raises Fpds::MalformedResponseError on non-JSON body" do
      stub_request(:get, %r{api\.sam\.gov/contract-awards/v1/search})
        .to_return(status: 200, body: "<html>Not JSON</html>")

      expect do
        described_class.new.raw_search(contractingDepartmentCode: "9700", limit: 1)
      end.to raise_error(Contractkit::Fpds::MalformedResponseError)
    end
  end
end
