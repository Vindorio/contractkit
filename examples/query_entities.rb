#!/usr/bin/env ruby
# frozen_string_literal: true

# Entity enrichment script.
# Demonstrates enriching USASpending-derived Recipients with full SAM
# Entity Management data — registration status, exclusions, business
# types, SBA certifications, corporate ownership hierarchy.
#
# How to run:
#   SAM_API_KEY=<your-key> bundle exec ruby examples/query_entities.rb
#
# Optional env vars:
#   NAICS=541512       # default: 541512 (Computer Systems Design)

require "bundler/setup"
require "contractkit"
require "date"

NAICS = ENV.fetch("NAICS", "541512")

Contractkit.configure do |c|
  c.user_agent = "contractkit-query-entities/1.0"
  c.retries    = 3
end

abort "Set SAM_API_KEY in env to run this example." if Contractkit.configuration.sam_api_key.to_s.empty?

# ---------------------------------------------------------------------------
# 1. Find awards with populated recipient UEIs
# ---------------------------------------------------------------------------
puts "\n== Finding awards for NAICS #{NAICS} with recipient UEIs ==\n"

awards = Contractkit::Award.search(
  filters: {
    naics_codes: [NAICS],
    time_period: [{ start_date: (Date.today - 365).iso8601, end_date: Date.today.iso8601 }]
  },
  per_page: 10,
  limit: 10
).first(10)

# Collect unique UEIs from awards
ueis = awards.filter_map { |a| a.recipient&.uei }.uniq.first(5)

puts "Found #{awards.size} awards, #{ueis.size} unique UEIs.\n"

# ---------------------------------------------------------------------------
# 2. Enrich each UEI with SAM Entity Management data
# ---------------------------------------------------------------------------
ueis.each_with_index do |uei, i|
  puts "--- Recipient ##{i + 1} (UEI: #{uei}) ---"

  begin
    recipient = Contractkit::Recipient.find_entity(uei)

    # Registration status
    puts "  Name              : #{recipient.name || 'N/A'}"
    puts "  CAGE Code         : #{recipient.cage_code || 'N/A'}"
    puts "  Registration      : #{recipient.registration_status || 'N/A'}"
    puts "  SAM Expiration    : #{recipient.sam_expiration_date || 'N/A'}"

    # Status checks
    if recipient.respond_to?(:excluded?)
      puts "  Excluded?         : #{recipient.excluded? ? 'YES ⚠️' : 'No'}"
    end
    if recipient.respond_to?(:registration_expired?)
      puts "  Reg. Expired?     : #{recipient.registration_expired? ? 'YES ⚠️' : 'No'}"
    end

    # Business types
    if recipient.respond_to?(:business_types) && recipient.business_types&.any?
      puts "  Business Types    :"
      recipient.business_types.each do |bt|
        puts "    - #{bt.code}: #{bt.description}"
      end
    end

    # SBA certifications
    if recipient.respond_to?(:sba_business_types) && recipient.sba_business_types&.any?
      puts "  SBA Certifications:"
      recipient.sba_business_types.each do |sba|
        puts "    - #{sba.code}: #{sba.description}"
      end
    end

    # NAICS list from SAM registration
    if recipient.respond_to?(:naics_list) && recipient.naics_list&.any?
      primary = recipient.naics_list.find { |n| n[:primary] }
      puts "  NAICS (primary)   : #{primary[:naics_code] || 'N/A'}" if primary
      puts "  NAICS (registered): #{recipient.naics_list.size} codes"
    end

    # Corporate ownership hierarchy
    if recipient.respond_to?(:immediate_owner) && recipient.immediate_owner
      puts "  Immediate Owner   : #{recipient.immediate_owner.name} (UEI: #{recipient.immediate_owner.uei})"
    end
    if recipient.respond_to?(:highest_owner) && recipient.highest_owner
      puts "  Highest Owner     : #{recipient.highest_owner.name} (UEI: #{recipient.highest_owner.uei})"
    end
    puts ""

  rescue Contractkit::AuthenticationError
    puts "  SAM auth rejected — check SAM_API_KEY and key scope.\n\n"
  rescue Contractkit::RateLimitError => e
    puts "  SAM rate-limited (Retry-After=#{e.retry_after}s).\n\n"
  rescue Contractkit::NotFoundError
    puts "  No entity found for UEI #{uei}.\n\n"
  rescue Contractkit::Error => e
    puts "  Error: #{e.class.name.split('::').last}: #{e.message}\n\n"
  end
end

# ---------------------------------------------------------------------------
# 3. Show un-enriched vs enriched comparison
# ---------------------------------------------------------------------------
puts "== Un-enriched vs Enriched Comparison ==\n"

award = awards.first
if award && award.recipient&.uei
  puts "  From Award (un-enriched):"
  puts "    Name: #{award.recipient.name || 'N/A'}"
  puts "    UEI:  #{award.recipient.uei || 'N/A'}"
  puts "    CAGE: #{award.recipient.respond_to?(:cage_code) ? award.recipient.cage_code || 'nil' : 'N/A'}"
  puts ""

  begin
    enriched = Contractkit::Recipient.find_entity(award.recipient.uei)
    puts "  After find_entity (enriched):"
    puts "    Name:       #{enriched.name || 'N/A'}"
    puts "    CAGE:       #{enriched.respond_to?(:cage_code) ? enriched.cage_code || 'nil' : 'N/A'}"
    puts "    Status:     #{enriched.respond_to?(:registration_status) ? enriched.registration_status || 'nil' : 'N/A'}"
    puts "    Excluded?:  #{enriched.respond_to?(:excluded?) ? enriched.excluded? : 'N/A'}"
    puts "    Bus. Types: #{enriched.respond_to?(:business_types) ? enriched.business_types&.size || 0 : 0}"
    puts "    SBA Types:  #{enriched.respond_to?(:sba_business_types) ? enriched.sba_business_types&.size || 0 : 0}"
  rescue Contractkit::Error => e
    puts "  Enrichment failed: #{e.message}"
  end
end

puts "\nDone.\n"
