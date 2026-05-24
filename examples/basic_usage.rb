#!/usr/bin/env ruby
# frozen_string_literal: true

# End-to-end smoke test of contractkit's M2 public surface.
#
# What this demonstrates (works today, after M2):
#   - Contractkit.configure with SAM_API_KEY from env
#   - Contractkit::Opportunity.search — record-level lazy iteration
#     (typed Opportunity objects, not raw JSON)
#   - Contractkit::Opportunity.search(...).each_batch — batch interface
#     (one Array<Opportunity> per upstream page; memory cost is one page
#     at a time, never accumulated)
#   - Contractkit::Award.search — same shape on the USASpending side
#   - opp.agency.code / opp.set_aside / opp.naics_code — normalized at
#     ingestion; consumers store the codes for indexed queries
#   - opp.related_awards / opp.likely_incumbent — cross-reference, the
#     flagship feature
#   - Block-hook instrumentation via c.on_event
#
# How to run:
#   SAM_API_KEY=<your-key> bundle exec ruby examples/basic_usage.rb
#
# Get a key at https://api.data.gov/signup/.

require "bundler/setup"
require "contractkit"
require "date"

Contractkit.configure do |c|
  c.user_agent = "contractkit-example-smoketest/2.0"
  c.timeout    = 30
  c.retries    = 3

  c.on_event do |name, payload|
    case name
    when "contractkit.request.start"
      puts "  -> #{payload[:method]} #{payload[:url].sub(/api_key=[^&]+/, "api_key=***")}"
    when "contractkit.request.finish"
      puts "     #{payload[:status]} in #{payload[:duration_ms]}ms"
    when "contractkit.rate_limit_wait"
      puts "  (paced #{payload[:wait_seconds]}s on #{payload[:host]})"
    end
  end
end

if Contractkit.configuration.sam_api_key.to_s.empty?
  abort "Set SAM_API_KEY in env to run this example."
end

# ---------------------------------------------------------------------------
# 1. SAM.gov — record-level iteration of typed Opportunity objects
# ---------------------------------------------------------------------------
puts "\n== SAM.gov: Contractkit::Opportunity.search (record-level) ==\n"

begin
  opps = Contractkit::Opportunity.search(
    ncode: "541512",
    per_page: 3,
    postedFrom: Date.today - 90,
    postedTo: Date.today
  ).first(3)

  puts "\nGot #{opps.size} Opportunity objects. First:\n"
  if (first = opps.first)
    puts "  notice_id        : #{first.notice_id}"
    puts "  title            : #{first.title&.slice(0, 80)}"
    puts "  agency.code      : #{first.agency.code.inspect}  (normalized at ingestion)"
    puts "  agency.name      : #{first.agency.name}"
    puts "  naics_code       : #{first.naics_code}"
    puts "  set_aside (sym)  : #{first.set_aside.inspect}"
    puts "  set_aside_code   : #{first.set_aside_code.inspect}  (raw SAM code; source of truth)"
    puts "  posted_at        : #{first.posted_at}"
    puts "  place_of_perf    : state=#{first.place_of_performance.state.inspect} " \
         "city=#{first.place_of_performance.city.inspect}"
  end
rescue Contractkit::Sam::RateLimitError => e
  puts "\n  SAM rate-limited (Retry-After=#{e.retry_after}s). Error path verified."
rescue Contractkit::Sam::AuthenticationError => e
  puts "\n  SAM rejected the key (#{e.status}). Check SAM_API_KEY."
end

# ---------------------------------------------------------------------------
# 2. SAM.gov — batch interface (one Array<Opportunity> per upstream page)
# ---------------------------------------------------------------------------
puts "\n== SAM.gov: Opportunity.search(...).each_batch ==\n"

begin
  Contractkit::Opportunity.search(
    ncode: "541512",
    per_page: 3,
    postedFrom: Date.today - 30,
    postedTo: Date.today
  ).each_batch.first(1).each do |batch|
    puts "  yielded batch of #{batch.size} typed Opportunity objects"
    # In a real consumer:  Contract.upsert_batch(batch.map(&:to_h))
  end
rescue Contractkit::Sam::RateLimitError => e
  puts "  SAM rate-limited (Retry-After=#{e.retry_after}s)."
end

# ---------------------------------------------------------------------------
# 3. USASpending — typed Award objects with BigDecimal money fields
# ---------------------------------------------------------------------------
puts "\n== USASpending: Contractkit::Award.search ==\n"

awards = Contractkit::Award.search(
  filters: {
    naics_codes: ["541512"],
    time_period: [{ start_date: (Date.today - 90).iso8601, end_date: Date.today.iso8601 }]
  },
  per_page: 3
).first(3)

puts "\nGot #{awards.size} Award objects. First:\n"
if (first_award = awards.first)
  puts "  award_id           : #{first_award.award_id}"
  puts "  recipient.name     : #{first_award.recipient&.name}"
  puts "  recipient.uei      : #{first_award.recipient&.uei}"
  puts "  obligated_amount   : $#{first_award.obligated_amount.to_s("F")}  (BigDecimal)"
  puts "  ceiling            : $#{first_award.ceiling&.to_s("F")}  (separate field)"
  puts "  awarding_agency    : code=#{first_award.awarding_agency.code.inspect}, " \
       "name=#{first_award.awarding_agency.name.inspect}"
  puts "  period             : #{first_award.period.start_date} → #{first_award.period.end_date}"
  puts "  pop.state          : #{first_award.place_of_performance&.state.inspect}"
end

# ---------------------------------------------------------------------------
# 4. Cross-reference — the flagship feature
# ---------------------------------------------------------------------------
puts "\n== Cross-reference: opportunity#related_awards + #likely_incumbent ==\n"

if opps.is_a?(Array) && opps.any?
  begin
    related = opps.first.related_awards(lookback: 3, limit: 5)
    puts "\nFor opportunity #{opps.first.notice_id} (#{opps.first.agency.code}, NAICS " \
         "#{opps.first.naics_code}):"
    puts "  related awards     : #{related.size}"
    related.first(3).each do |a|
      puts "    - #{a.recipient&.name&.slice(0, 50)} :: $#{a.obligated_amount&.to_s("F")}"
    end

    incumbent = Contractkit::CrossReference.likely_incumbent(related)
    incumbent_str = incumbent ? "#{incumbent.name} (UEI #{incumbent.uei})" : "nil (ambiguous)"
    puts "  likely incumbent   : #{incumbent_str}"
  rescue Contractkit::Error => e
    puts "  Cross-reference error: #{e.class.name.split("::").last}: #{e.message}"
  end
else
  puts "  (skipped — no SAM opportunity to cross-reference against)"
end

# ---------------------------------------------------------------------------
# 5. Multi-tenant pattern — per-tenant Client isolation
# ---------------------------------------------------------------------------
puts "\n== Per-tenant Client (instance-scoped config) ==\n"

tenant_client = Contractkit::Client.new(
  sam_api_key: Contractkit.configuration.sam_api_key,
  timeout: 15
)
puts "  global timeout  : #{Contractkit.configuration.timeout}"
puts "  tenant timeout  : #{tenant_client.configuration.timeout}"
puts "  (independent — mutating one doesn't affect the other)"

puts "\nSmoke test complete."
