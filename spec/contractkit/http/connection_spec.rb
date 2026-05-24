# frozen_string_literal: true

require "stringio"
require "logger"

RSpec.describe Contractkit::Http::Connection do
  let(:config) { Contractkit::Configuration.new(retries: 3, timeout: 30) }

  # Specs use Faraday's test adapter to drive retry behavior deterministically
  # without WebMock cassettes or real network. Live-network specs live in
  # Sam/Usaspending client specs (M1.5+).
  def build_with(config, stubs)
    described_class.build(config) do |conn|
      conn.adapter :test, stubs
    end
  end

  describe "timeouts" do
    it "wires read timeout from config and open timeout to 5s" do
      conn = described_class.build(Contractkit::Configuration.new(timeout: 42))
      expect(conn.options.timeout).to      eq(42)
      expect(conn.options.open_timeout).to eq(5)
    end
  end

  describe "user agent" do
    it "carries the configured user-agent header" do
      conn = described_class.build(Contractkit::Configuration.new)
      expect(conn.headers["User-Agent"]).to include("contractkit/")
    end
  end

  describe "retry policy" do
    # faraday-retry's Test-adapter quirk: each stub is consumed on match,
    # so we register one stub per expected attempt. The first call gets
    # the first stub, retry gets the second, etc.
    it "retries a 500 then succeeds on the next attempt" do
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("/flaky") { [500, {}, "boom"] }
        s.get("/flaky") { [200, {}, "ok"] }
      end

      response = build_with(config, stubs).get("/flaky")
      expect(response.status).to eq(200)
      expect(response.body).to   eq("ok")
      stubs.verify_stubbed_calls
    end

    it "does not retry a 401" do
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("/no-auth") { [401, {}, "unauthorized"] }
      end

      response = build_with(config, stubs).get("/no-auth")
      expect(response.status).to eq(401)
      stubs.verify_stubbed_calls
    end

    it "does not retry a 429 (delegated to the rate limiter middleware in #11)" do
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("/rate-limited") { [429, { "Retry-After" => "5" }, "slow"] }
      end

      response = build_with(config, stubs).get("/rate-limited")
      expect(response.status).to eq(429)
      stubs.verify_stubbed_calls
    end

    it "returns the failed response after exhausting retries on persistent 503" do
      attempts = 4 # initial + 3 retries (the default)
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        attempts.times { s.get("/down") { [503, {}, "unavailable"] } }
      end

      conn = build_with(Contractkit::Configuration.new(retries: 3, timeout: 30), stubs)
      response = conn.get("/down")
      expect(response.status).to eq(503)
      stubs.verify_stubbed_calls
    end
  end

  describe "redaction in logs" do
    it "scrubs api_key from logged URLs" do
      io = StringIO.new
      logger = Logger.new(io)
      logger.formatter = ->(_, _, _, msg) { "#{msg}\n" }

      logging_config = Contractkit::Configuration.new(logger: logger, retries: 0)
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("/search") { [200, {}, "ok"] }
      end

      build_with(logging_config, stubs)
        .get("/search", api_key: "SAM-secret-12345", ncode: "541512")

      log_output = io.string
      expect(log_output).to     include("api_key=[REDACTED]")
      expect(log_output).not_to include("SAM-secret-12345")
      expect(log_output).to     include("ncode=541512") # non-secret param untouched
    end
  end
end
