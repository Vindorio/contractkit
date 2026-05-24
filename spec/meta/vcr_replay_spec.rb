# frozen_string_literal: true

require "faraday"

# Meta-spec: VCR is wired correctly. With `:vcr` metadata, the
# request below is served from a committed cassette
# (spec/fixtures/cassettes/meta/vcr_replay_spec/<example>.yml) rather
# than the real network. If this fails after the cassette is committed,
# VCR is misconfigured or the cassette has drifted.
RSpec.describe "VCR cassette replay", :vcr do
  it "serves a recorded HTTP response from disk" do
    response = Faraday.get("https://example.test/ping")
    expect(response.status).to eq(200)
    expect(response.body).to include("ok")
  end
end
