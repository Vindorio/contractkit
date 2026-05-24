# frozen_string_literal: true

RSpec.describe Contractkit::Http::RateLimiter::Bucket do
  # Deterministic clock so timing-based assertions don't depend on wall time.
  let(:now) { 1000.0 }
  let(:clock) do
    t = now.dup
    -> { t }
  end

  describe "#take with sufficient tokens" do
    it "decrements the bucket and returns 0 wait" do
      bucket = described_class.new(capacity: 5, rate: 1.0, clock: -> { now })
      expect(bucket.take).to eq(0.0)
      expect(bucket.tokens).to be_within(0.001).of(4)
    end
  end

  describe "#take when bucket is empty (real sleep)" do
    it "blocks for the time it takes to refill one token" do
      bucket = described_class.new(capacity: 1, rate: 4.0) # 4 tokens/sec = 250ms per token
      bucket.take # consume the only token
      elapsed = measure { bucket.take }
      # Should sleep ~250ms (with some scheduling slop)
      expect(elapsed).to be_between(0.2, 0.5)
    end
  end

  describe "#drain" do
    it "pushes tokens negative so the next take blocks for the drain window" do
      bucket = described_class.new(capacity: 10, rate: 10.0) # 100ms refill per token
      bucket.drain(0.3) # next take should block ~400ms (-3 + 1 = 4 tokens worth at 10/sec)
      elapsed = measure { bucket.take }
      expect(elapsed).to be_between(0.3, 0.6)
    end
  end

  def measure
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  end
end

RSpec.describe Contractkit::Http::RateLimiter do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  def build_conn(host_rates: {})
    Faraday.new(url: "https://api.sam.gov") do |c|
      c.use described_class, host_rates: host_rates
      c.adapter :test, stubs
    end
  end

  describe "request pacing" do
    it "paces successive requests at the configured rate" do
      stubs.get("/x") { [200, {}, "ok"] }
      stubs.get("/x") { [200, {}, "ok"] }
      stubs.get("/x") { [200, {}, "ok"] }

      # 2 tokens/sec, capacity 1 = 500ms between requests after the first.
      conn = build_conn(host_rates: { "api.sam.gov" => { capacity: 1, rate: 2.0 } })

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      3.times { conn.get("/x") }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

      # First request immediate; next two each wait ~500ms.
      expect(elapsed).to be_between(0.9, 1.5)
      stubs.verify_stubbed_calls
    end
  end

  describe "429 handling" do
    it "raises the SAM rate-limit error and drains the bucket by Retry-After" do
      stubs.get("/blocked") { [429, { "Retry-After" => "1" }, "slow down"] }

      conn = build_conn(host_rates: { "api.sam.gov" => { capacity: 10, rate: 10.0 } })

      expect { conn.get("/blocked") }
        .to raise_error(Contractkit::Sam::RateLimitError) do |err|
          expect(err.retry_after).to eq(1.0)
          expect(err.status).to eq(429)
          expect(err.endpoint).to include("/blocked")
        end
    end

    it "next request after a 429 with Retry-After=1 waits ~1s" do
      stubs.get("/blocked") { [429, { "Retry-After" => "1" }, ""] }
      stubs.get("/blocked") { [200, {}, "ok"] }

      conn = build_conn(host_rates: { "api.sam.gov" => { capacity: 10, rate: 10.0 } })

      begin
        conn.get("/blocked")
      rescue Contractkit::Sam::RateLimitError
        # expected
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      conn.get("/blocked")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed

      expect(elapsed).to be_between(0.8, 1.5)
    end
  end

  describe "unknown hosts" do
    it "does not throttle when the host is not in the rate table" do
      example_stubs = Faraday::Adapter::Test::Stubs.new
      5.times { example_stubs.get("/y") { [200, {}, "ok"] } }
      conn = Faraday.new(url: "https://api.example.test") do |c|
        c.use described_class
        c.adapter :test, example_stubs
      end

      elapsed = measure { 5.times { conn.get("/y") } }
      expect(elapsed).to be < 0.1
    end
  end

  def measure
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  end
end
