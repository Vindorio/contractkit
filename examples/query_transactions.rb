#!/usr/bin/env ruby
# frozen_string_literal: true

# Transaction query script.
# Demonstrates fetching and analyzing the per-modification transaction
# history for USASpending awards — shows how to detect option exercises,
# track ceiling growth, and reconstruct obligation timelines.
#
# How to run:
#   SAM_API_KEY=<your-key> bundle exec ruby examples/query_transactions.rb
#
# Optional env vars:
#   NAICS=541512       # default: 541512 (Computer Systems Design)

require "bundler/setup"
require "contractkit"
require "date"
require "bigdecimal"

NAICS = ENV.fetch("NAICS", "541512")

Contractkit.configure do |c|
  c.user_agent = "contractkit-query-transactions/1.0"
  c.retries    = 3
end

# This example only hits USASpending (no SAM key needed for awards/transactions),
# but we still configure for completeness.

# ---------------------------------------------------------------------------
# 1. Find a few awards to analyze
# ---------------------------------------------------------------------------
puts "\n== Finding awards for NAICS #{NAICS} with recent transactions ==\n"

awards = Contractkit::Award.search(
  filters: {
    naics_codes: [NAICS],
    time_period: [{ start_date: (Date.today - 365).iso8601, end_date: Date.today.iso8601 }]
  },
  per_page: 5,
  limit: 5
).first(5)

puts "Found #{awards.size} awards.\n"

# ---------------------------------------------------------------------------
# 2. Fetch transactions for each award and analyze
# ---------------------------------------------------------------------------
awards.each_with_index do |award, i|
  puts "--- Award ##{i + 1} ---"
  puts "  PIID            : #{award.piid || 'N/A'}"
  puts "  Award ID        : #{award.award_id}"
  puts "  Recipient       : #{award.recipient&.name || 'N/A'}"
  puts "  Obligated       : $#{award.obligated_amount&.to_s('F') || 'N/A'}"
  puts "  Period          : #{award.period&.start_date} → #{award.period&.end_date}"

  begin
    txs = award.transactions

    if txs.empty?
      puts "  Transactions    : none returned"
      puts ""
      next
    end

    puts "  Transactions    : #{txs.size}"
    puts ""

    # Summarize by action_type
    by_action = txs.group_by { |t| t.action_type&.description || "Unknown" }
    puts "  By action type:"
    by_action.sort_by { |_, v| -v.size }.each do |action, group|
      total = group.sum(BigDecimal("0")) { |t| t.federal_action_obligation || 0 }
      puts "    #{action}: #{group.size} mods, $#{total.to_s('F')} net"
    end

    # Option exercise detection (consumer heuristic — gem doesn't do this)
    options = txs.select { |t| t.action_type&.code == "G" }
    puts ""
    puts "  Explicit option exercises (code 'G'): #{options.size}" if options.any?

    # Base award
    base = txs.find { |t| t.modification_number == "P00000" }
    puts "  Base award (P00000): #{base&.action_date} — $#{base&.federal_action_obligation&.to_s('F')}" if base

    # Timeline summary
    puts ""
    puts "  Timeline (first 3 and last 3):"
    txs.first(3).each do |t|
      puts "    #{t.modification_number} | #{t.action_date} | $#{t.federal_action_obligation&.to_s('F') || '0'} | #{t.action_type&.description || '?'}"
    end
    puts "    ..." if txs.size > 6
    txs.last(3).each do |t|
      puts "    #{t.modification_number} | #{t.action_date} | $#{t.federal_action_obligation&.to_s('F') || '0'} | #{t.action_type&.description || '?'}"
    end
    puts ""
  rescue Contractkit::Error => e
    puts "  Error: #{e.class.name.split('::').last}: #{e.message}"
    puts ""
  end
end

puts "Done.\n"
