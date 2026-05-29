#!/usr/bin/env ruby
# frozen_string_literal: true

# IDV (Indefinite-Delivery Vehicle) query script.
# Demonstrates searching for expiring IDVs, parent/child traversal,
# and using last_date_to_order as a recompete signal.
#
# How to run:
#   SAM_API_KEY=<your-key> bundle exec ruby examples/query_idvs.rb
#
# Optional env vars:
#   NAICS=541512       # default: 541512 (Computer Systems Design)

require "bundler/setup"
require "contractkit"
require "date"

NAICS = ENV.fetch("NAICS", "541512")

Contractkit.configure do |c|
  c.user_agent = "contractkit-query-idvs/1.0"
  c.retries    = 3
end

abort "Set SAM_API_KEY in env to run this example." if Contractkit.configuration.sam_api_key.to_s.empty?

# ---------------------------------------------------------------------------
# 1. Search for IDVs (indefinite-delivery vehicles) in a NAICS code
# ---------------------------------------------------------------------------
puts "\n== Searching IDVs for NAICS #{NAICS} ==\n"

begin
  idvs = Contractkit::Idv.search(
    filters: {
      naics_codes: [NAICS],
      time_period: [{ start_date: (Date.today - 365).iso8601, end_date: Date.today.iso8601 }]
    },
    per_page: 10,
    limit: 5
  ).first(5)

  puts "Found #{idvs.size} IDVs.\n"
  idvs.each_with_index do |idv, i|
    puts "--- IDV ##{i + 1} ---"
    puts "  PIID               : #{idv.piid}"
    puts "  Type               : #{idv.award_type}"
    puts "  Obligated          : $#{idv.obligated_amount&.to_s('F') || 'N/A'}"
    puts "  Ceiling            : $#{idv.total_contract_value&.to_s('F') || 'N/A'}"
    puts "  Last Date to Order : #{idv.last_date_to_order || 'N/A'}"
    puts "  Period End         : #{idv.period_end_date || 'N/A'}"
    puts "  Recipient          : #{idv.recipient&.name || 'N/A'}"
    puts "  Agency             : #{idv.awarding_agency&.code || 'N/A'}"

    # Recompete signal: is this IDV expiring soon?
    if idv.last_date_to_order
      months_left = ((idv.last_date_to_order - Date.today) / 30.0).round(1)
      signal = if months_left <= 0
                 "EXPIRED"
               elsif months_left <= 6
                 "URGENT (#{months_left} months)"
               elsif months_left <= 18
                 "recompete window (#{months_left} months)"
               else
                 "distant (#{months_left} months)"
               end
      puts "  Recompete signal   : #{signal}"
    end
  end
rescue Contractkit::Error => e
  puts "  Error: #{e.class.name.split('::').last}: #{e.message}"
end

# ---------------------------------------------------------------------------
# 2. Parent/child traversal — if we found an IDV, list its task orders
# ---------------------------------------------------------------------------
if idvs.is_a?(Array) && idvs.any?
  puts "\n== Child task orders for first IDV ==\n"

  idv = idvs.first
  begin
    children = idv.child_awards
    puts "IDV #{idv.piid} has #{children.size} child awards.\n"
    children.first(5).each do |child|
      puts "  - #{child.piid || child.award_id}"
      puts "    Type: #{child.award_type || 'N/A'}"
      puts "    Obligated: $#{child.obligated_amount&.to_s('F') || 'N/A'}"
      puts "    Period: #{child.period&.start_date} → #{child.period&.end_date}"
      puts ""
    end
  rescue Contractkit::Error => e
    puts "  Error fetching children: #{e.message}"
  end
end

# ---------------------------------------------------------------------------
# 3. Use Recompete helper for time-forward scan
# ---------------------------------------------------------------------------
puts "\n== Recompete.expiring(within: 12) for NAICS #{NAICS} ==\n"

begin
  count = 0
  Contractkit::Recompete.expiring(within: 12, naics: NAICS, limit: 5) do |match|
    count += 1
    award_type = match.award.is_a?(Contractkit::Idv) ? "IDV" : "Contract"
    puts "--- Match ##{count} (#{award_type}) ---"
    puts "  Award PIID        : #{match.award.piid}"
    puts "  Expiration        : #{match.award.respond_to?(:last_date_to_order) ? match.award.last_date_to_order : match.award.period&.end_date}"
    puts "  SAM matches       : #{match.matching_opportunities.size}"
    match.matching_opportunities.first(3).each do |opp|
      puts "    - #{opp.notice_id&.slice(0, 12)}: #{opp.title&.slice(0, 60)}"
    end
  end
  puts "\n  #{count} expiring awards found with matching SAM opportunities."
rescue Contractkit::Error => e
  puts "  Error: #{e.class.name.split('::').last}: #{e.message}"
end

puts "\nDone.\n"
