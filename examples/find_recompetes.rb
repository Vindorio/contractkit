#!/usr/bin/env ruby
# frozen_string_literal: true

# Recompete-detection canonical script — the gem's flagship use case.
#
# Pulls recent SAM.gov opportunities for a NAICS code, looks up related
# historical USASpending awards for each, identifies the likely incumbent
# when one recipient dominates the obligation history, and prints a
# summary table.
#
# How to run:
#   SAM_API_KEY=<your-key> bundle exec ruby examples/find_recompetes.rb
#
# Optional environment variables:
#   NAICS=541512               # default: 541512 (Computer Systems Design)
#   LOOKBACK_DAYS=90           # opportunity-posted window
#   AWARD_LOOKBACK_YEARS=3     # historical award lookback for related_awards
#   MAX_OPPS=10                # cap on opportunities to inspect

require "bundler/setup"
require "contractkit"
require "date"

NAICS                = ENV.fetch("NAICS", "541512")
LOOKBACK_DAYS        = Integer(ENV.fetch("LOOKBACK_DAYS", "90"))
AWARD_LOOKBACK_YEARS = Integer(ENV.fetch("AWARD_LOOKBACK_YEARS", "3"))
MAX_OPPS             = Integer(ENV.fetch("MAX_OPPS", "10"))

Contractkit.configure do |c|
  c.user_agent = "contractkit-find-recompetes/1.0"
  c.retries    = 3
end

if Contractkit.configuration.sam_api_key.to_s.empty?
  abort "Set SAM_API_KEY in env to run this example."
end

puts "Searching SAM.gov for NAICS=#{NAICS} opportunities posted in last " \
     "#{LOOKBACK_DAYS} days..."

opps =
  begin
    Contractkit::Opportunity.search(
      ncode: NAICS,
      per_page: [MAX_OPPS, 100].min,
      postedFrom: Date.today - LOOKBACK_DAYS,
      postedTo: Date.today
    ).first(MAX_OPPS)
  rescue Contractkit::Sam::RateLimitError => e
    abort "SAM rate-limited (Retry-After=#{e.retry_after}s). Try again later."
  rescue Contractkit::Sam::AuthenticationError => e
    abort "SAM rejected the key (#{e.status}). Check SAM_API_KEY."
  end

puts "Found #{opps.size} opportunities. Cross-referencing each against " \
     "USASpending awards (lookback #{AWARD_LOOKBACK_YEARS}y)...\n\n"

# Pre-compute the cross-reference column data for each opportunity.
rows = opps.map do |opp|
  related = begin
    opp.related_awards(lookback: AWARD_LOOKBACK_YEARS, limit: 50)
  rescue Contractkit::Error => e
    warn "  cross-ref error for #{opp.notice_id}: #{e.class.name.split("::").last}"
    []
  end

  incumbent = Contractkit::CrossReference.likely_incumbent(related)
  total = related.sum(BigDecimal("0")) { |a| a.obligated_amount || BigDecimal("0") }

  {
    notice_id: opp.notice_id&.slice(0, 12),
    agency: opp.agency.code || opp.agency.name&.slice(0, 8),
    set_aside: opp.set_aside,
    title: opp.title&.slice(0, 40),
    related_count: related.size,
    incumbent: incumbent&.name&.slice(0, 32) || "—",
    total_obligated: total
  }
end

# Pretty-print summary table.
def fmt_money(value)
  return "—" if value.nil? || value.zero?

  "$#{value.to_i.to_s.reverse.scan(/.{1,3}/).join(",").reverse}"
end

# rubocop:disable Layout/LineLength
puts "NOTICE         AGENCY   SET-ASIDE    TITLE                                     AWARDS LIKELY INCUMBENT                  TOTAL"
# rubocop:enable Layout/LineLength
puts "-" * 160
rows.each do |r|
  puts format(
    "%<notice_id>-14s  %<agency>-8s  %<set_aside>-12s  %<title>-42s  " \
    "%<related_count>-6d  %<incumbent>-34s  %<total>s",
    notice_id: r[:notice_id], agency: r[:agency], set_aside: r[:set_aside],
    title: r[:title], related_count: r[:related_count], incumbent: r[:incumbent],
    total: fmt_money(r[:total_obligated])
  )
end

puts "\nDone. #{rows.count { |r| r[:incumbent] != "—" }} likely incumbents detected " \
     "across #{rows.size} opportunities."
