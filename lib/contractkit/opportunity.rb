# frozen_string_literal: true

module Contractkit
  # Normalized SAM.gov opportunity. Plain Ruby value object — no
  # ActiveRecord, no inheritance. Built by {Contractkit::Sam::ResponseParser}.
  #
  # See docs/design/data-models.md for the field map and rationale.
  # `.raw` exposes the original SAM JSON for any field the gem doesn't
  # surface; `.to_h` returns the normalized hash.
  class Opportunity
    attr_reader :notice_id, :title, :solicitation_number,
                :agency,
                :posted_at, :response_deadline_at, :archive_at,
                :notice_type, :notice_base_type,
                :naics_code, :psc_code,
                :set_aside_code, :set_aside, :set_aside_label,
                :place_of_performance,
                :contacts, :description,
                :additional_info_url, :links, :attachments,
                :award,
                :raw

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      notice_id:, title:,
      solicitation_number: nil,
      agency: nil,
      posted_at: nil, response_deadline_at: nil, archive_at: nil,
      notice_type: nil, notice_base_type: nil,
      naics_code: nil, psc_code: nil,
      set_aside_code: nil, set_aside: :none, set_aside_label: nil,
      place_of_performance: nil,
      contacts: [], description: nil,
      additional_info_url: nil, links: [], attachments: [],
      award: nil,
      raw: nil
    )
      @notice_id            = notice_id
      @title                = title
      @solicitation_number  = solicitation_number
      @agency               = agency
      @posted_at            = posted_at
      @response_deadline_at = response_deadline_at
      @archive_at           = archive_at
      @notice_type          = notice_type
      @notice_base_type     = notice_base_type
      @naics_code           = naics_code
      @psc_code             = psc_code
      @set_aside_code       = set_aside_code
      @set_aside            = set_aside
      @set_aside_label      = set_aside_label
      @place_of_performance = place_of_performance
      @contacts             = contacts.freeze
      @description          = description
      @additional_info_url  = additional_info_url
      @links                = links.freeze
      @attachments          = attachments.freeze
      @award                = award
      @raw                  = raw
      freeze
    end
    # rubocop:enable Metrics/ParameterLists

    def to_h
      {
        notice_id: notice_id,
        title: title,
        solicitation_number: solicitation_number,
        agency: agency&.to_h,
        posted_at: posted_at,
        response_deadline_at: response_deadline_at,
        archive_at: archive_at,
        notice_type: notice_type,
        notice_base_type: notice_base_type,
        naics_code: naics_code,
        psc_code: psc_code,
        set_aside_code: set_aside_code,
        set_aside: set_aside,
        set_aside_label: set_aside_label,
        place_of_performance: place_of_performance&.to_h,
        contacts: contacts,
        description: description,
        additional_info_url: additional_info_url,
        links: links,
        attachments: attachments,
        award: award
      }
    end

    def ==(other)
      other.is_a?(Opportunity) && notice_id == other.notice_id
    end
    alias eql? ==

    def hash
      notice_id.hash
    end
  end
end
