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

    # Awards likely related to this opportunity. Delegates to
    # {Contractkit::CrossReference.awards_for}. See cross-reference docs
    # for matching strategy.
    def related_awards(**)
      Contractkit::CrossReference.awards_for(opportunity: self, **)
    end

    # Returns the dominant recipient (>50% of obligation across related
    # awards) as a {Contractkit::Recipient}, or nil when ambiguous. See
    # {Contractkit::CrossReference.likely_incumbent}.
    def likely_incumbent(**)
      Contractkit::CrossReference.likely_incumbent(related_awards(**))
    end

    # ----------------------------------------------------------------
    # Resource-module surface — module-level convenience over the global
    # configuration. Multi-tenant consumers pass a Client.new explicitly
    # to .search / .find / .modified_since via the `client:` keyword.
    # ----------------------------------------------------------------

    class << self
      # Returns a lazy {OpportunitySearch} over SAM matching the filters.
      # Iteration is record-level by default (.each yields Opportunity);
      # callers needing the batch interface use #each_batch.
      def search(client: nil, naics: nil, **params)
        params[:naics] = naics if naics
        OpportunitySearch.new(client: client || default_client, params: params)
      end

      # Fetches a single Opportunity by SAM noticeId. Raises
      # {Contractkit::NotFoundError} when no match exists.
      def find(notice_id, client: nil)
        result = (client || default_client).raw_search(noticeid: notice_id)
        records = result["opportunitiesData"] || []
        if records.empty?
          raise Contractkit::NotFoundError.new(
            "no SAM opportunity found for noticeId=#{notice_id.inspect}",
            endpoint: Contractkit::Sam::Client::BASE_URL, http_method: :get,
            params: { noticeid: notice_id }
          )
        end

        Contractkit::Sam::ResponseParser.parse(records.first)
      end

      # Yields each Opportunity posted on or after the given time. With a
      # block, fires per-record; without, returns an OpportunitySearch
      # enumerator. `time` accepts Date, DateTime, Time.
      def modified_since(time, client: nil, **params, &block)
        result = search(
          client: client,
          postedFrom: to_date(time),
          postedTo: Date.today,
          **params
        )
        return result.each(&block) if block

        result
      end

      private

      def default_client
        Contractkit::Sam::Client.new
      end

      def to_date(value)
        return value if value.is_a?(Date) && !value.is_a?(DateTime)

        value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
      end
    end
  end
end
