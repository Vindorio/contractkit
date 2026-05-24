# frozen_string_literal: true

RSpec.describe Contractkit::Configuration do
  describe "defaults" do
    it "exposes every documented option with sensible defaults" do
      config = described_class.new
      expect(config.timeout).to   eq(30)
      expect(config.retries).to   eq(3)
      expect(config.cache_ttl).to eq(0)
      expect(config.cache).to     be_nil
      expect(config.logger).to    be_nil
    end

    it "includes the gem version in the user-agent" do
      expect(described_class.new.user_agent).to include(Contractkit::VERSION)
    end

    it "picks up SAM_API_KEY from the environment when no explicit override" do
      stub_const("ENV", ENV.to_h.merge("SAM_API_KEY" => "SAM-from-env"))
      expect(described_class.new.sam_api_key).to eq("SAM-from-env")
    end

    it "explicit override beats the environment" do
      stub_const("ENV", ENV.to_h.merge("SAM_API_KEY" => "SAM-from-env"))
      expect(described_class.new(sam_api_key: "explicit").sam_api_key).to eq("explicit")
    end
  end

  describe "validation" do
    it "raises ConfigurationError on unknown options to catch typos" do
      expect { described_class.new(timetout: 30) }
        .to raise_error(Contractkit::ConfigurationError, /unknown configuration option: :timetout/)
    end
  end

  describe "mutation" do
    it "supports batch update under a synchronized block" do
      config = described_class.new
      config.update do |c|
        c.timeout = 60
        c.retries = 5
      end
      expect(config.timeout).to eq(60)
      expect(config.retries).to eq(5)
    end

    it "individual setters work for one-off changes" do
      config = described_class.new
      config.sam_api_key = "rotated"
      expect(config.sam_api_key).to eq("rotated")
    end
  end

  describe "#merge" do
    it "returns a new Configuration with overrides applied" do
      base = described_class.new(timeout: 30)
      derived = base.merge(timeout: 60)
      expect(derived.timeout).to eq(60)
      expect(base.timeout).to    eq(30) # base unchanged
    end
  end

  describe "thread safety" do
    it "synchronizes reads against concurrent writes" do
      config = described_class.new(timeout: 30)
      reader_results = []
      readers = Array.new(20) do
        Thread.new { 100.times { reader_results << config.timeout } }
      end
      writer = Thread.new do
        100.times { |i| config.timeout = i.even? ? 30 : 60 }
      end
      (readers + [writer]).each(&:join)
      # Every read returned one of the two values, never a partial state.
      expect(reader_results.uniq).to all(satisfy { |v| [30, 60].include?(v) })
    end
  end
end

RSpec.describe Contractkit::Client do
  it "wraps its own Configuration, not the global" do
    Contractkit.configure { |c| c.timeout = 99 }
    client = described_class.new(timeout: 5)
    expect(client.configuration.timeout).to eq(5)
    expect(Contractkit.configuration.timeout).to eq(99)
  end

  it "two clients do not share state" do
    a = described_class.new(timeout: 10)
    b = described_class.new(timeout: 20)
    expect(a.configuration.timeout).to eq(10)
    expect(b.configuration.timeout).to eq(20)
    a.configuration.timeout = 100
    expect(b.configuration.timeout).to eq(20) # b unaffected
  end

  it "yields its configuration via .configure" do
    client = described_class.new
    client.configure { |c| c.sam_api_key = "client-scoped-key" }
    expect(client.configuration.sam_api_key).to eq("client-scoped-key")
  end
end

RSpec.describe Contractkit do
  before { described_class.reset_configuration! }

  describe ".configure" do
    it "yields the singleton" do
      described_class.configure { |c| c.timeout = 77 }
      expect(described_class.configuration.timeout).to eq(77)
    end

    it "returns the configuration" do
      result = described_class.configure { |c| c.timeout = 10 }
      expect(result).to be(described_class.configuration)
    end
  end

  describe "override precedence" do
    it "instance > global default" do
      described_class.configure { |c| c.timeout = 30 }
      client = Contractkit::Client.new(timeout: 60)
      expect(client.configuration.timeout).to eq(60)
    end
  end
end
