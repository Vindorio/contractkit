# frozen_string_literal: true

require "date"

module Contractkit
  # Federal contract recipient (the awardee). Identified by UEI since
  # 2022 (DUNS is retained on legacy awards for historical lookup).
  #
  # ## M4 (#39): SAM.gov Entity Management enrichment
  #
  # The bulk of #attribute lists below are populated only when the
  # Recipient is constructed via {Contractkit::Sam::Entities.find} (UEI
  # lookup against `/entity-information/v3/entities`). USASpending-built
  # Recipients (those that come back from a spending_by_award parse) only
  # carry name/uei/duns/recipient_id — every other field is nil. This is
  # intentional: entity enrichment is opt-in and requires an extra SAM
  # API call. See docs/domain/entities.md.
  class Recipient
    attr_reader :name, :uei, :duns, :recipient_id,
                # Registration
                :registration_status,
                :registration_date,
                :sam_expiration_date,
                :last_update_date,
                :purpose_of_registration,
                # Identity
                :cage_code,
                :dodaac,
                :legal_business_name,
                :dba_name,
                # Classification
                :business_types,
                :sba_business_types,
                :naics_list,
                :psc_codes,
                # Exclusions
                :exclusion_status_flag,
                :exclusion_status_description,
                # Corporate hierarchy
                :immediate_owner,
                :highest_owner,
                :predecessors,
                :raw

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      name:,
      uei: nil, duns: nil, recipient_id: nil,
      registration_status: nil,
      registration_date: nil,
      sam_expiration_date: nil,
      last_update_date: nil,
      purpose_of_registration: nil,
      cage_code: nil,
      dodaac: nil,
      legal_business_name: nil,
      dba_name: nil,
      business_types: [],
      sba_business_types: [],
      naics_list: [],
      psc_codes: [],
      exclusion_status_flag: nil,
      exclusion_status_description: nil,
      immediate_owner: nil,
      highest_owner: nil,
      predecessors: [],
      raw: nil
    )
      @name         = name
      @uei          = uei
      @duns         = duns
      @recipient_id = recipient_id

      @registration_status     = registration_status
      @registration_date       = registration_date
      @sam_expiration_date     = sam_expiration_date
      @last_update_date        = last_update_date
      @purpose_of_registration = purpose_of_registration

      @cage_code           = cage_code
      @dodaac              = dodaac
      @legal_business_name = legal_business_name
      @dba_name            = dba_name

      @business_types     = (business_types || []).freeze
      @sba_business_types = (sba_business_types || []).freeze
      @naics_list         = (naics_list || []).freeze
      @psc_codes          = (psc_codes || []).freeze

      @exclusion_status_flag        = exclusion_status_flag
      @exclusion_status_description = exclusion_status_description

      @immediate_owner = immediate_owner
      @highest_owner   = highest_owner
      @predecessors    = (predecessors || []).freeze

      @raw = raw
      freeze
    end
    # rubocop:enable Metrics/ParameterLists

    # @return [Hash] flat hash of all fields (for serialization).
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def to_h
      {
        name: name, uei: uei, duns: duns, recipient_id: recipient_id,
        registration_status: registration_status,
        registration_date: registration_date,
        sam_expiration_date: sam_expiration_date,
        last_update_date: last_update_date,
        purpose_of_registration: purpose_of_registration&.to_h,
        cage_code: cage_code,
        dodaac: dodaac,
        legal_business_name: legal_business_name,
        dba_name: dba_name,
        business_types: business_types.map { |b| b.respond_to?(:to_h) ? b.to_h : b },
        sba_business_types: sba_business_types.map { |b| b.respond_to?(:to_h) ? b.to_h : b },
        naics_list: naics_list,
        psc_codes: psc_codes,
        exclusion_status_flag: exclusion_status_flag,
        exclusion_status_description: exclusion_status_description,
        immediate_owner: immediate_owner&.to_h,
        highest_owner: highest_owner&.to_h,
        predecessors: predecessors.map { |p| p.respond_to?(:to_h) ? p.to_h : p }
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Value-equality by (uei, name). Two recipients with the same UEI but
    # different captured names compare unequal — names drift across awards
    # for the same entity, so the pair is safer than UEI alone.
    def ==(other)
      other.is_a?(Recipient) && uei == other.uei && name == other.name
    end
    alias eql? ==

    # @return [Integer] hash code matching the equality contract.
    def hash
      [uei, name].hash
    end

    # True when SAM has flagged this entity as excluded (debarred,
    # suspended, or proposed for debarment). Returns false when the
    # entity has been enriched via SAM Entities and is clean; nil when
    # the Recipient hasn't been enriched (USASpending-only construction).
    def excluded?
      exclusion_status_flag
    end

    # True when SAM expiration is in the past as of `today`. nil when
    # sam_expiration_date isn't set (un-enriched Recipient).
    def registration_expired?(today: Date.today)
      return false if sam_expiration_date.nil?

      sam_expiration_date < today
    end

    # Fetches a Recipient by UEI via USASpending's
    # /api/v2/recipient/duns/{uei}/ endpoint (the "duns" path is legacy
    # — the API moved to UEI in 2022 but kept the URL stable).
    #
    # Raises {Contractkit::NotFoundError} when the UEI isn't on file.
    def self.find(uei, client: nil)
      raw = (client || Contractkit::Usaspending::Client.new).raw_recipient(uei)

      new(
        name: raw["name"] || raw["recipient_name"],
        uei: raw["uei"] || uei,
        duns: raw["duns"],
        recipient_id: raw["recipient_id"] || raw["id"],
        raw: raw
      )
    end

    # Fetches the SAM Entity Management record for `uei` and returns a
    # Recipient with the full registration/identity/classification/owner
    # surface populated. Requires a SAM API key. See
    # {Contractkit::Sam::Entities.find}.
    def self.find_entity(uei, client: nil)
      Contractkit::Sam::Entities.find(uei, client: client)
    end
  end

  # Small value object for SAM corporate-hierarchy references (immediate
  # owner / highest owner / predecessor). Always carries the minimal
  # identity triple that SAM exposes for owner records.
  class OwnerReference
    attr_reader :uei, :name, :cage_code

    def initialize(uei: nil, name: nil, cage_code: nil)
      @uei       = uei
      @name      = name
      @cage_code = cage_code
      freeze
    end

    def to_h
      { uei: uei, name: name, cage_code: cage_code }
    end

    def ==(other)
      other.is_a?(OwnerReference) && to_h == other.to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end
  end
end
