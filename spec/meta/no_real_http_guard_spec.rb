# frozen_string_literal: true

require "faraday"

# Meta-spec: the gem's testing posture is "no test ever talks to the
# real network." This spec asserts that posture by attempting an
# unstubbed real-URL request from a spec WITHOUT :vcr metadata and
# confirming that something (either VCR or WebMock) blocks it.
#
# In practice VCR's request handler fires first when allow_http_connections
# _when_no_cassette is false, raising UnhandledHTTPRequestError. If VCR
# is misconfigured, WebMock's NetConnectNotAllowedError is the backstop.
# Either is acceptable — what matters is the request never reaches the
# network. If this spec ever passes (no error raised), some part of the
# suite is exfiltrating real HTTP — investigate before merging.
RSpec.describe "no-real-HTTP guard" do
  it "blocks unstubbed network requests outside :vcr cassettes" do
    expect { Faraday.get("https://example.test/forbidden") }
      .to raise_error(
        an_instance_of(VCR::Errors::UnhandledHTTPRequestError)
          .or(an_instance_of(WebMock::NetConnectNotAllowedError))
      )
  end
end
