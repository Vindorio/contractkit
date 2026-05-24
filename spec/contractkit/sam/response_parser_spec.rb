# frozen_string_literal: true

RSpec.describe Contractkit::Sam::ResponseParser do
  let(:full_notice) do
    {
      "noticeId" => "abc-123-def",
      "title" => "IT Modernization Services",
      "solicitationNumber" => "FA8771-26-R-0042",
      "fullParentPathName" => "DEPARTMENT OF DEFENSE.DEPT OF THE AIR FORCE.AFMC",
      "department" => "DEPARTMENT OF DEFENSE",
      "postedDate" => "2026-04-15T13:00:00-04:00",
      "responseDeadLine" => "2026-05-15T17:00:00-04:00",
      "archiveDate" => "2026-08-15",
      "type" => "Solicitation",
      "baseType" => "Solicitation",
      "naicsCode" => "541512",
      "classificationCode" => "D316",
      "typeOfSetAside" => "8A",
      "typeOfSetAsideDescription" => "8(a) Set-Aside",
      "placeOfPerformance" => {
        "state" => { "code" => "VA", "name" => "Virginia" },
        "city" => "Arlington",
        "country" => "USA",
        "zip" => "22202"
      },
      "pointOfContact" => [{ "fullName" => "Jane Doe", "email" => "jane@example.mil" }],
      "description" => "Long description here",
      "additionalInfoLink" => "https://example.mil/info",
      "links" => [{ "rel" => "self", "href" => "https://api.sam.gov/..." }],
      "resourceLinks" => ["https://attachment.example.mil/1.pdf"],
      "award" => nil
    }
  end

  describe ".parse on a full notice" do
    let(:opp) { described_class.parse(full_notice) }

    it "returns a frozen Opportunity instance" do
      expect(opp).to be_a(Contractkit::Opportunity)
      expect(opp).to be_frozen
    end

    it "carries the basic scalar fields" do
      expect(opp.notice_id).to            eq("abc-123-def")
      expect(opp.title).to                eq("IT Modernization Services")
      expect(opp.solicitation_number).to  eq("FA8771-26-R-0042")
      expect(opp.notice_type).to          eq("Solicitation")
      expect(opp.naics_code).to           eq("541512")
      expect(opp.psc_code).to             eq("D316")
    end

    it "parses dates and datetimes" do
      expect(opp.posted_at).to            be_a(DateTime)
      expect(opp.response_deadline_at).to be_a(DateTime)
      expect(opp.archive_at).to           eq(Date.new(2026, 8, 15))
    end

    it "normalizes the agency to a canonical Contractkit::Agency" do
      expect(opp.agency).to be_a(Contractkit::Agency)
      expect(opp.agency.code).to eq("DOD")
      expect(opp.agency.name).to eq("Department of Defense")
    end

    it "normalizes the set-aside to both the raw SAM code and the Ruby symbol" do
      expect(opp.set_aside_code).to  eq("8A")
      expect(opp.set_aside).to       eq(:sba_8a)
      expect(opp.set_aside_label).to eq("8(a) Set-Aside")
    end

    it "normalizes place_of_performance to the value object (with state code)" do
      expect(opp.place_of_performance).to be_a(Contractkit::PlaceOfPerformance)
      expect(opp.place_of_performance.state).to eq("VA")
      expect(opp.place_of_performance.city).to  eq("Arlington")
    end

    it "preserves arrays (contacts, links, attachments) and keeps .raw intact" do
      expect(opp.contacts.size).to    eq(1)
      expect(opp.links.size).to       eq(1)
      expect(opp.attachments.size).to eq(1)
      expect(opp.raw).to be(full_notice)
    end
  end

  describe "agency normalization" do
    it "falls back to a raw-string Agency when the input is unknown" do
      hash = full_notice.merge(
        "fullParentPathName" => "AGENCY OF MADE-UP THINGS",
        "department" => nil
      )
      opp = described_class.parse(hash)
      expect(opp.agency.code).to be_nil
      expect(opp.agency.name).to eq("AGENCY OF MADE-UP THINGS")
    end
  end

  describe "placeOfPerformance polymorphism" do
    it "handles state as a plain string" do
      hash = full_notice.merge(
        "placeOfPerformance" => { "state" => "VA", "city" => "Arlington" }
      )
      opp = described_class.parse(hash)
      expect(opp.place_of_performance.state).to eq("VA")
    end

    it "handles state as a {code, name} object" do
      opp = described_class.parse(full_notice)
      expect(opp.place_of_performance.state).to eq("VA")
    end

    it "tolerates a missing placeOfPerformance" do
      opp = described_class.parse(full_notice.merge("placeOfPerformance" => nil))
      expect(opp.place_of_performance.state).to be_nil
    end
  end

  describe "naicsCode normalization" do
    it "passes through a 6-digit string" do
      opp = described_class.parse(full_notice.merge("naicsCode" => "541512"))
      expect(opp.naics_code).to eq("541512")
    end

    it "zero-pads a 5-character code (integer in JSON)" do
      opp = described_class.parse(full_notice.merge("naicsCode" => 11_220))
      expect(opp.naics_code).to eq("011220")
    end

    it "passes through nil" do
      opp = described_class.parse(full_notice.merge("naicsCode" => nil))
      expect(opp.naics_code).to be_nil
    end
  end

  describe "sparse notice (lots of nils)" do
    let(:sparse) { { "noticeId" => "sparse-1", "title" => "Bare bones" } }

    it "parses without raising and surfaces nils for missing fields" do
      opp = described_class.parse(sparse)
      expect(opp.notice_id).to eq("sparse-1")
      expect(opp.naics_code).to be_nil
      expect(opp.set_aside).to  eq(:none)
      expect(opp.agency.code).to be_nil
      expect(opp.contacts).to    eq([])
    end
  end

  describe "set-aside safe-normalize behavior" do
    it "unknown set-aside codes resolve to :unknown rather than raising" do
      opp = described_class.parse(full_notice.merge("typeOfSetAside" => "WEIRDXX"))
      expect(opp.set_aside).to       eq(:unknown)
      expect(opp.set_aside_code).to  eq("WEIRDXX")
    end
  end

  describe ".parse_batch" do
    it "maps an array of notices to an array of Opportunities" do
      result = described_class.parse_batch([full_notice, full_notice.merge("noticeId" => "b")])
      expect(result.size).to eq(2)
      expect(result).to all(be_a(Contractkit::Opportunity))
    end
  end
end
