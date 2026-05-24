# frozen_string_literal: true

# Minimal in-process cache satisfying the contract config.cache expects:
# #read(key) -> value | nil; #write(key, value, ttl:) -> value.
class StubCache
  attr_reader :store, :writes

  def initialize
    @store  = {}
    @writes = []
  end

  def read(key)
    @store[key]
  end

  def write(key, value, ttl: 0)
    @store[key] = value
    @writes << [key, ttl]
    value
  end
end

RSpec.describe Contractkit::Http::CacheMiddleware do
  let(:cache) { StubCache.new }

  def build_conn(config, stubs)
    Contractkit::Http::Connection.build(config) { |c| c.adapter :test, stubs }
  end

  describe "cache miss → real request → write" do
    it "fetches from the upstream and writes to the cache" do
      config = Contractkit::Configuration.new(cache: cache, cache_ttl: 60, retries: 0)
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("/x") { [200, { "Content-Type" => "application/json" }, '{"a":1}'] }
      end

      response = build_conn(config, stubs).get("/x")

      expect(response.status).to eq(200)
      expect(response.body).to   eq('{"a":1}')
      expect(cache.writes.size).to eq(1)
      expect(cache.writes.first.last).to eq(60) # ttl
      stubs.verify_stubbed_calls
    end
  end

  describe "cache hit → no upstream call" do
    it "returns the cached response without invoking the adapter" do
      config = Contractkit::Configuration.new(cache: cache, cache_ttl: 60, retries: 0)

      stubs_first = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("/x") { [200, { "X-Source" => "live" }, "live-body"] }
      end
      build_conn(config, stubs_first).get("/x") # populate cache
      stubs_first.verify_stubbed_calls

      # New adapter with no stubs registered — if the cache fails, the
      # adapter would raise NotFound. A passing test proves the hit was served
      # entirely from cache.
      empty_stubs = Faraday::Adapter::Test::Stubs.new
      response = build_conn(config, empty_stubs).get("/x")

      expect(response.status).to eq(200)
      expect(response.body).to   eq("live-body")
      expect(response.headers["X-Source"]).to eq("live")
    end
  end

  describe "non-GET requests" do
    it "passes POST through without cache interaction" do
      config = Contractkit::Configuration.new(cache: cache, retries: 0)
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.post("/y") { [200, {}, "ok"] }
      end

      build_conn(config, stubs).post("/y", '{"k":"v"}')

      expect(cache.writes).to be_empty
    end
  end

  describe "nil cache short-circuit" do
    it "passes through with zero cache interaction when config.cache is nil" do
      config = Contractkit::Configuration.new(cache: nil, retries: 0)
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("/z") { [200, {}, "ok"] }
      end

      response = build_conn(config, stubs).get("/z")
      expect(response.status).to eq(200)
    end
  end

  describe "non-2xx responses" do
    it "does not cache a 500" do
      config = Contractkit::Configuration.new(cache: cache, retries: 0)
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("/down") { [500, {}, "boom"] }
      end

      build_conn(config, stubs).get("/down")

      expect(cache.writes).to be_empty
    end
  end

  describe "query string ordering" do
    it "treats ?a=1&b=2 and ?b=2&a=1 as the same cache key" do
      config = Contractkit::Configuration.new(cache: cache, retries: 0)
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("/x") { |env| [200, {}, env.url.query.to_s] }
      end

      conn = build_conn(config, stubs)
      first = conn.get("/x", a: 1, b: 2)
      # Second request would 404 if not served from cache — empty stubs
      conn_empty = build_conn(config, Faraday::Adapter::Test::Stubs.new)
      second = conn_empty.get("/x", b: 2, a: 1)

      expect(second.body).to eq(first.body)
    end
  end
end
