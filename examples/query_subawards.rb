#!/usr/bin/env ruby
# frozen_string_literal: true

# Subaward query script.
# Demonstrates fetching subaward (prime → sub teaming) data for awards.
# Shows how to analyze teaming patterns — which primes subcontract
# to which subs, and how subaward dollars compare to the prime award.
#
# How to run:
#   SAM_API_KEY=<your-key> bundle exec ruby examples/query_subawards.rb
#
# Optional env vars:
#   NAICS=541512       # default: 541512 (Computer Systems Design)

require "bundler/setup"
require "contractkit"
require "date"
require "bigdecimal"

NAICS = ENV.fetch("NAICS", "541512")

Contractkit.configure do |c|
  c.user_agent = "contractkit-query-subawards/1.0"
  c.retries    = 3
end

# ---------------------------------------------------------------------------
# 1. Find awards with significant obligated amounts
# ---------------------------------------------------------------------------
puts "\n== Finding awards for NAICS #{NAICS} ==\n"

awards = Contractkit::Award.search(
  filters: {
    naics_codes: [NAICS],
    time_period: [{ start_date: (Date.today - 365 * 2).iso8601, end_date: Date.today.iso8601 }]
  },
  per_page: 5,
  limit: 5
).first(5)

puts "Found #{awards.size} awards.\n"

# ---------------------------------------------------------------------------
# 2. Fetch subawards for each award and analyze teaming patterns
# ---------------------------------------------------------------------------
awards.each_with_index do |award, i|
  puts "--- Award ##{i + 1} ---"
  puts "  PIID            : #{award.piid || 'N/A'}"
  puts "  Recipient (prime): #{award.recipient&.name || 'N/A'}"
  puts "  Prime UEI       : #{award.recipient&.uei || 'N/A'}"
  puts "  Obligated       : $#{award.obligated_amount&.to_s('F') || 'N/A'}"
  puts "  Ceiling         : $#{award.ceiling&.to_s('F') || 'N/A'}"

  begin
    subs = award.subawards

    if subs.empty?
      puts "  Subawards       : none reported (or below FFATA threshold)"
      puts ""
      next
    end

    puts "  Subawards       : #{subs.size}"
    puts ""

    # Summarize by sub-recipient
    by_sub = subs.group_by { |s| s.sub_recipient_name || "Unknown" }
    sub_totals = by_sub.transform_values do |list|
      list.sum(BigDecimal("0")) { |s| s.amount || 0 }
    end

    puts "  Sub-recipients and amounts:"
    sub_totals.sort_by { |_, v| -v }.each do |name, total|
      count = by_sub[name].size
      puts "    #{name}: $#{total.to_s('F')} (#{count} subawards)"
    end

    # Comparison: what fraction is subcontracted?
    total_subs = sub_totals.values.sum(BigDecimal("0"))
    if award.obligated_amount && award.obligated_amount > 0
      sub_ratio = (total_subs / award.obligated_amount * 100).round(1)
      puts ""
      puts "  Subcontract ratio: #{sub_ratio}% of prime award"
    end

    # Show subaward details for the first few
    puts ""
    puts "  First 3 subawards:"
    subs.first(3).each do |s|
      puts "    ##{s.subaward_number || '?'} | #{s.action_date} | $#{s.amount&.to_s('F') || '?'}"
      puts "      Sub: #{s.sub_recipient_name || 'N/A'} (UEI #{s.sub_recipient_uei || 'N/A'})"
      puts "      NAICS: #{s.naics_code || 'N/A'}"
    end
    puts ""
  rescue Contractkit::Error => e
    puts "  Error: #{e.class.name.split('::').last}: #{e.message}"
    puts ""
  end
end

puts "Done.\n"
