# frozen_string_literal: true

require "date"

module Contractkit
  module Sam
    # Translates a single SAM.gov notice hash (one element of
    # opportunitiesData) into a {Contractkit::Opportunity} value object.
    #
    # Field-by-field translations are deliberately dumb — no scoring, no
    # cross-API enrichment, no API calls. Just hash → object. Cross-API
    # work (Opportunity#related_awards) lives in CrossReference.
    module ResponseParser
      # @param hash [Hash] one SAM opportunity hash
      # @return [Contractkit::Opportunity]
      # rubocop:disable Metrics/AbcSize -- field mapping is inherently wide
      def self.parse(hash)
        Contractkit::Opportunity.new(
          notice_id: hash["noticeId"],
          title: hash["title"],
          solicitation_number: presence(hash["solicitationNumber"]),
          agency: Contractkit::Agency.normalize(extract_agency_top(hash)),
          posted_at: parse_datetime(hash["postedDate"]),
          response_deadline_at: parse_datetime(hash["responseDeadLine"]),
          archive_at: parse_date(hash["archiveDate"]),
          notice_type: hash["type"],
          notice_base_type: hash["baseType"],
          naics_code: normalize_naics(hash["naicsCode"]),
          psc_code: presence(hash["classificationCode"]),
          set_aside_code: presence(hash["typeOfSetAside"]),
          set_aside: Contractkit::SetAside.safe_normalize(
            hash["typeOfSetAside"] || hash["typeOfSetAsideDescription"]
          ),
          set_aside_label: presence(hash["typeOfSetAsideDescription"]),
          place_of_performance: Contractkit::PlaceOfPerformance.from_sam(hash["placeOfPerformance"]),
          contacts: Array(hash["pointOfContact"]),
          description: presence(hash["description"]),
          additional_info_url: presence(hash["additionalInfoLink"]),
          links: Array(hash["links"]),
          attachments: Array(hash["resourceLinks"]),
          award: hash["award"] || hash["awardee"],
          raw: hash
        )
      end
      # rubocop:enable Metrics/AbcSize

      # Yields per notice in opportunitiesData — used by the resource module
      # to wrap raw batch hashes into Opportunity objects.
      def self.parse_batch(batch)
        batch.map { |notice| parse(notice) }
      end

      class << self
        private

        def presence(value)
          return nil if value.nil?
          return nil if value.is_a?(String) && value.strip.empty?

          value
        end

        # SAM's `fullParentPathName` is dot-delimited (e.g.
        # "DEPT OF DEFENSE.DEPT OF THE AIR FORCE.AFMC..."). Vindor's
        # convention (preserved per extraction-plan #3): the top-level
        # department is the first segment. Agency.normalize then resolves
        # it to a canonical Agency.
        def extract_agency_top(hash)
          full = hash["fullParentPathName"]
          return hash["department"] if full.nil?

          full.split(".", 2).first
        end

        # SAM's naicsCode comes as either a 6-digit string ("541512") or
        # as an integer (e.g. 11220, losing the leading zero). Normalize
        # to a 6-character zero-padded string.
        def normalize_naics(value)
          return nil if value.nil?

          value.to_s.strip.rjust(6, "0")[0, 6]
        end

        # Date::Error is a subclass of ArgumentError in Ruby 3+; rescuing
        # ArgumentError covers both. Listing both would shadow.
        def parse_datetime(value)
          return nil if value.nil? || value.to_s.strip.empty?

          DateTime.iso8601(value.to_s)
        rescue ArgumentError
          begin
            DateTime.parse(value.to_s)
          rescue ArgumentError
            nil
          end
        end

        def parse_date(value)
          return nil if value.nil? || value.to_s.strip.empty?

          Date.parse(value.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
