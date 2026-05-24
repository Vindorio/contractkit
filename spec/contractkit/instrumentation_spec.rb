# frozen_string_literal: true

RSpec.describe Contractkit::Instrumentation do
  before do
    Contractkit.reset_configuration!
  end

  describe ".emit (block hook)" do
    it "calls the configured on_event block with name + payload" do
      received = []
      Contractkit.configure { |c| c.on_event { |name, payload| received << [name, payload] } }

      described_class.emit("contractkit.request.start", url: "https://example.test/x")

      expect(received).to eq(
        [["contractkit.request.start", { url: "https://example.test/x" }]]
      )
    end

    it "is a no-op when no on_event block is registered" do
      expect { described_class.emit("contractkit.error", {}) }.not_to raise_error
    end

    it "scoped to the passed Configuration (Client-scoped emission)" do
      global_received = []
      Contractkit.configure { |c| c.on_event { |n, p| global_received << [n, p] } }

      isolated_received = []
      client = Contractkit::Client.new
      client.configure { |c| c.on_event { |n, p| isolated_received << [n, p] } }

      described_class.emit("contractkit.retry", { attempt: 1 }, config: client.configuration)

      expect(isolated_received).to eq([["contractkit.retry", { attempt: 1 }]])
      expect(global_received).to be_empty
    end
  end

  describe ".emit (ActiveSupport::Notifications)" do
    # AS 7.x requires its core loaded before Notifications can resolve
    # IsolatedExecutionState — `require "active_support/notifications"`
    # alone isn't enough on a cold load. Re-requires are no-ops, so doing
    # this per-example is cheap and avoids before(:context) leak warnings.
    before do
      require "active_support"
      require "active_support/isolated_execution_state"
      require "active_support/notifications"
    end

    it "publishes through AS::Notifications when AS is loaded" do
      received = []
      sub = ActiveSupport::Notifications.subscribe(/^contractkit\./) do |name, *args|
        received << [name, args.last]
      end

      described_class.emit("contractkit.request.finish", status: 200, duration_ms: 45.2)

      expect(received.size).to eq(1)
      expect(received.first.first).to eq("contractkit.request.finish")
      expect(received.first.last).to include(status: 200, duration_ms: 45.2)
    ensure
      ActiveSupport::Notifications.unsubscribe(sub) if sub
    end
  end
end

RSpec.describe Contractkit::Http::InstrumentationMiddleware do
  let(:received) { [] }

  before do
    Contractkit.reset_configuration!
    received_buffer = received
    Contractkit.configure { |c| c.on_event { |n, p| received_buffer << [n, p] } }
  end

  it "emits request.start and request.finish around a normal call" do
    stubs = Faraday::Adapter::Test::Stubs.new { |s| s.get("/ok") { [200, {}, "ok"] } }
    conn = Contractkit::Http::Connection.build(Contractkit::Configuration.new(retries: 0)) do |c|
      c.adapter :test, stubs
    end

    conn.get("/ok")

    names = received.map(&:first)
    expect(names).to include("contractkit.request.start", "contractkit.request.finish")

    finish = received.find { |n, _| n == "contractkit.request.finish" }.last
    expect(finish[:status]).to eq(200)
    expect(finish[:duration_ms]).to be >= 0
  end

  it "emits a retry event for each retry attempt" do
    stubs = Faraday::Adapter::Test::Stubs.new do |s|
      4.times { s.get("/fail") { [500, {}, ""] } }
    end
    conn = Contractkit::Http::Connection.build(Contractkit::Configuration.new(retries: 2)) do |c|
      c.adapter :test, stubs
    end

    conn.get("/fail")

    retries = received.select { |n, _| n == "contractkit.retry" } # rubocop:disable Style/HashSlice
    expect(retries.size).to eq(2) # 2 retries after initial 500
  end
end
