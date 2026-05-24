# frozen_string_literal: true

require "contractkit"

require "vcr"
require "webmock/rspec"

# Auto-load any shared helpers, matchers, or shared contexts.
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

VCR.configure do |c|
  c.cassette_library_dir = File.expand_path("fixtures/cassettes", __dir__)
  c.hook_into :webmock
  c.configure_rspec_metadata!

  # Keep secrets out of recorded cassettes. Any SAM.gov API key seen in
  # a request URL or query param is rewritten to <SAM_API_KEY> before
  # the cassette hits disk. The env var name (SAM_API_KEY) matches what
  # the gem reads via Configuration.
  c.filter_sensitive_data("<SAM_API_KEY>") { ENV.fetch("SAM_API_KEY", nil) }

  # Custom matcher: match request URLs ignoring the api_key query param.
  # Required because the cassette stores the redacted "<SAM_API_KEY>"
  # placeholder, but on replay (with no env var set) VCR can't substitute
  # back — so a literal-URL match would always fail in CI. Comparing
  # without the api_key lets the cassette replay regardless of what
  # api_key value the test happened to set.
  c.register_request_matcher(:uri_ignoring_api_key) do |req1, req2|
    [req1, req2].map do |r|
      uri = URI(r.uri)
      query = (uri.query || "").split("&")
                               .reject { |kv| kv.start_with?("api_key=") }
                               .sort.join("&")
      "#{uri.scheme}://#{uri.host}#{uri.path}?#{query}"
    end.uniq.size == 1 && req1.method == req2.method
  end

  # Refresh policy: cassettes are committed and replayed by default.
  # To re-record against live APIs (rare; needs a SAM key in env):
  #   VCR=new_episodes bundle exec rspec spec/<path>
  # See docs/design/packaging.md § Testing strategy.
  c.default_cassette_options = {
    record: ENV.fetch("VCR", "none").to_sym,
    match_requests_on: %i[method uri_ignoring_api_key]
  }

  # When no cassette is in scope, raise rather than passing through to
  # the real network. Matches the WebMock guard below; belt-and-braces.
  c.allow_http_connections_when_no_cassette = false
end

# WebMock guard — every spec runs with the network off. Specs that need
# realistic responses opt in via `:vcr` metadata. allow_localhost: true
# keeps in-process stubs that bind to 127.0.0.1 from breaking.
# Order matters: must come AFTER VCR.configure, because VCR's webmock
# hook installation resets webmock's allow-net flag.
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
