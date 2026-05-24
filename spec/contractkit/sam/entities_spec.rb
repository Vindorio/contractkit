# frozen_string_literal: true

RSpec.describe Contractkit::Sam::Entities do
  let(:active_small_business_entity) do
    {
      "entityRegistration" => {
        "ueiSAM" => "ABC123XYZ456",
        "ueiDUNS" => "987654321",
        "legalBusinessName" => "ACME ANALYTICS LLC",
        "dbaName" => "ACME",
        "cageCode" => "12345",
        "registrationStatus" => "Active",
        "registrationDate" => "2018-04-10",
        "registrationExpirationDate" => "2027-04-10",
        "lastUpdateDate" => "2026-03-15",
        "purposeOfRegistrationCode" => "Z2",
        "purposeOfRegistrationDesc" => "All Awards",
        "exclusionStatusFlag" => "N"
      },
      "coreData" => {
        "entityInformation" => {
          "legalBusinessName" => "ACME ANALYTICS LLC"
        },
        "businessTypes" => {
          "businessTypeList" => [
            { "businessTypeCode" => "2X", "businessTypeDesc" => "For Profit Organization" }
          ],
          "sbaBusinessTypeList" => [
            { "sbaBusinessTypeCode" => "A6",
              "sbaBusinessTypeDesc" => "8(a) Program Participant" }
          ]
        },
        "immediateOwner" => {
          "ueiSAM" => "PARENT001UEI",
          "legalBusinessName" => "ACME HOLDINGS CORP",
          "cageCode" => "P0001"
        },
        "highestLevelOwner" => {
          "ueiSAM" => "TOP001UEI",
          "legalBusinessName" => "ACME GLOBAL HOLDINGS",
          "cageCode" => "T0001"
        }
      },
      "assertions" => {
        "goodsAndServices" => {
          "naicsList" => [
            { "naicsCode" => "541512", "naicsDescription" => "Computer Systems Design",
              "isPrimary" => "Y", "sbaSmallBusiness" => "Y" },
            { "naicsCode" => "541511", "naicsDescription" => "Custom Computer Programming",
              "isPrimary" => "N", "sbaSmallBusiness" => "Y" }
          ],
          "pscList" => [{ "pscCode" => "D316" }, { "pscCode" => "R425" }]
        }
      }
    }
  end

  let(:expired_entity) do
    {
      "entityRegistration" => {
        "ueiSAM" => "EXPIRED01",
        "legalBusinessName" => "STALE LLC",
        "registrationStatus" => "Expired",
        "registrationExpirationDate" => "2024-01-01",
        "exclusionStatusFlag" => "N"
      }
    }
  end

  let(:debarred_entity) do
    {
      "entityRegistration" => {
        "ueiSAM" => "DEBARRED1",
        "legalBusinessName" => "BAD ACTORS INC",
        "registrationStatus" => "Active",
        "exclusionStatusFlag" => "Y"
      },
      "coreData" => {
        "exclusionInformation" => {
          "exclusionStatusFlag" => "Y",
          "exclusionStatusDescription" => "Active exclusion — debarment"
        }
      }
    }
  end

  describe ".find via injected client" do
    it "wraps a single entityRegistration response in a Recipient" do
      client = instance_double(described_class::Client, raw_find: active_small_business_entity)
      recipient = described_class.find("ABC123XYZ456", client: client)

      expect(recipient).to be_a(Contractkit::Recipient)
      expect(recipient.uei).to eq("ABC123XYZ456")
      expect(recipient.registration_status).to eq("Active")
      expect(recipient.sam_expiration_date).to eq(Date.new(2027, 4, 10))
      expect(recipient.cage_code).to eq("12345")
    end

    it "unwraps the entityData array shape from search responses" do
      wrapped = { "entityData" => [active_small_business_entity] }
      client = instance_double(described_class::Client, raw_find: wrapped)
      r = described_class.find("ABC", client: client)
      expect(r.uei).to eq("ABC123XYZ456")
    end

    it "raises NotFoundError when SAM returns no records" do
      client = instance_double(described_class::Client, raw_find: { "entityData" => [] })
      expect { described_class.find("nope", client: client) }
        .to raise_error(Contractkit::NotFoundError, /not found/)
    end
  end

  describe "small-business + SBA + owner enrichment" do
    let(:r) do
      client = instance_double(described_class::Client, raw_find: active_small_business_entity)
      described_class.find("ABC123XYZ456", client: client)
    end

    it "exposes business_types and sba_business_types as CodedValue arrays" do
      expect(r.business_types.first).to be_a(Contractkit::CodedValue)
      expect(r.business_types.first.code).to eq("2X")
      expect(r.sba_business_types.first.code).to eq("A6")
    end

    it "exposes naics_list with primary + small_business flags" do
      primary = r.naics_list.find { |n| n[:primary] }
      expect(primary[:code]).to eq("541512")
      expect(primary[:small_business]).to be true
      expect(r.naics_list.size).to eq(2)
    end

    it "exposes immediate_owner and highest_owner as OwnerReference" do
      expect(r.immediate_owner).to be_a(Contractkit::OwnerReference)
      expect(r.immediate_owner.uei).to eq("PARENT001UEI")
      expect(r.highest_owner.name).to eq("ACME GLOBAL HOLDINGS")
    end

    it "marks excluded? as false for a clean entity" do
      expect(r.excluded?).to be false
    end
  end

  describe "expired registration" do
    it "flags registration_expired? = true when expiration is past" do
      client = instance_double(described_class::Client, raw_find: expired_entity)
      r = described_class.find("EXPIRED01", client: client)
      expect(r.registration_status).to eq("Expired")
      expect(r.registration_expired?(today: Date.new(2026, 5, 1))).to be true
    end
  end

  describe "debarred entity" do
    it "surfaces excluded? = true" do
      client = instance_double(described_class::Client, raw_find: debarred_entity)
      r = described_class.find("DEBARRED1", client: client)
      expect(r.excluded?).to be true
      expect(r.exclusion_status_description).to match(/debarment/)
    end
  end

  describe "USASpending-built recipients stay un-enriched" do
    it "leaves SAM fields nil when constructed from a spending_by_award row" do
      row = {
        "Award ID" => "X",
        "Recipient Name" => "ACME CORP",
        "Recipient UEI" => "UEI12345"
      }
      a = Contractkit::Usaspending::ResponseParser.parse(row)
      expect(a.recipient.uei).to eq("UEI12345")
      expect(a.recipient.cage_code).to be_nil
      expect(a.recipient.registration_status).to be_nil
      expect(a.recipient.excluded?).to be_nil
    end
  end
end
