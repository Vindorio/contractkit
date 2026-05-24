#!/usr/bin/env ruby
# frozen_string_literal: true

# End-to-end smoke test of contractkit's M1 public surface.
#
# What this demonstrates (works today, after M1):
#   - Contractkit.configure with SAM_API_KEY from env
#   - Contractkit::Sam::Client#raw_search and #search (lazy paginated)
#   - Contractkit::Usaspending::Client#raw_search and #search
#   - Block-hook instrumentation registered via c.on_event
#   - Per-host rate limiting (visible as small delays between calls)
#
# What's NOT here yet (arrives in M2):
#   - Contractkit::Opportunity / Award resource modules
#   - .find, .related_awards, .likely_incumbent on Opportunity
#   - Typed model objects (everything below is raw JSON hashes)
#
# How to run:
#   SAM_API_KEY=<your-key> bundle exec ruby examples/basic_usage.rb
#
# Get a key at https://api.data.gov/signup/.

require "bundler/setup"
require "contractkit"
require "date"

# ---------------------------------------------------------------------------
# 1. Configure once at boot. SAM_API_KEY is read from env automatically; the
# block here just adds the instrumentation hook.
# ---------------------------------------------------------------------------
Contractkit.configure do |c|
  c.user_agent = "contractkit-example-smoketest/1.0"
  c.timeout    = 30
  c.retries    = 3

  c.on_event do |name, payload|
    case name
    when "contractkit.request.start"
      puts "  -> #{payload[:method]} #{payload[:url].sub(/api_key=[^&]+/, "api_key=***")}"
    when "contractkit.request.finish"
      puts "     #{payload[:status]} in #{payload[:duration_ms]}ms"
    when "contractkit.rate_limit_wait"
      puts "  (paced #{payload[:wait_seconds]}s by rate limiter on #{payload[:host]})"
    end
  end
end

if Contractkit.configuration.sam_api_key.to_s.empty?
  abort "Set SAM_API_KEY in env to run this example."
end

# ---------------------------------------------------------------------------
# 2. SAM.gov: pull a handful of recent IT-services opportunities.
# ---------------------------------------------------------------------------
puts "\n== SAM.gov: opportunities ==\n"

sam = Contractkit::Sam::Client.new

begin
  opps = sam.search(
    ncode: "541512", # Computer Systems Design Services
    per_page: 3,
    postedFrom: Date.today - 90,
    postedTo: Date.today
  ).take(5)

  puts "\nGot #{opps.size} opportunities. First:\n"
  if (first = opps.first)
    puts "  noticeId:           #{first["noticeId"]}"
    puts "  title:              #{first["title"]&.slice(0, 80)}"
    puts "  agency (full path): #{first["fullParentPathName"]&.split(".")&.first}"
    puts "  posted:             #{first["postedDate"]}"
    puts "  response deadline:  #{first["responseDeadLine"]}"
    puts "  naics:              #{first["naicsCode"]}"
  end
rescue Contractkit::Sam::RateLimitError => e
  puts "\n  SAM rate-limited us (Retry-After=#{e.retry_after}s). The error path " \
       "worked — that's the smoke-test signal. Try again in a minute."
rescue Contractkit::Sam::AuthenticationError => e
  puts "\n  SAM rejected the key (#{e.status}). Check SAM_API_KEY env var."
end

# ---------------------------------------------------------------------------
# 3. USASpending: pull a few contract awards in the same NAICS, same quarter.
# ---------------------------------------------------------------------------
puts "\n== USASpending: recent contract awards ==\n"

usa = Contractkit::Usaspending::Client.new

begin
  awards = usa.search(
    filters: {
      naics_codes: ["541512"],
      time_period: [{ start_date: (Date.today - 90).iso8601, end_date: Date.today.iso8601 }]
    },
    limit: 3
  ).take(5)

  puts "\nGot #{awards.size} awards. First:\n"
  if (first_award = awards.first)
    puts "  Award ID:        #{first_award["Award ID"]}"
    puts "  Recipient:       #{first_award["Recipient Name"]}"
    puts "  Amount:          #{first_award["Award Amount"]}"
    puts "  Awarding Agency: #{first_award["Awarding Agency"]}"
    puts "  PoP State:       #{first_award["Place of Performance State Code"]}"
  end
rescue Contractkit::Usaspending::ServerError => e
  puts "\n  USASpending returned #{e.status}. Often transient — try again."
end

# ---------------------------------------------------------------------------
# 4. Multi-tenant pattern: per-tenant Client doesn't share state with the global.
# ---------------------------------------------------------------------------
puts "\n== Per-tenant Client (instance-scoped config) ==\n"

tenant_client = Contractkit::Client.new(
  sam_api_key: Contractkit.configuration.sam_api_key,
  timeout: 15
)
puts "  global timeout : #{Contractkit.configuration.timeout}"
puts "  tenant timeout : #{tenant_client.configuration.timeout}"
puts "  (independent — mutating one doesn't affect the other)"

puts "\nSmoke test complete. M2 will replace the raw-JSON paths above " \
     "with typed Opportunity/Award objects."
