# frozen_string_literal: true

RSpec.describe Contractkit::Error do
  let(:fields) do
    {
      endpoint: "https://api.sam.gov/opportunities/v2/search",
      http_method: :get,
      params: { ncode: "541512" },
      status: 500,
      response_snippet: "<html>500 Internal Server Error</html>"
    }
  end

  describe "field carriage" do
    it "carries every diagnostic field as a reader" do
      err = described_class.new("oops", **fields)
      expect(err.message).to          eq("oops")
      expect(err.endpoint).to         eq(fields[:endpoint])
      expect(err.http_method).to      eq(:get)
      expect(err.params).to           eq(ncode: "541512")
      expect(err.status).to           eq(500)
      expect(err.response_snippet).to include("500 Internal")
    end

    it "tolerates missing fields (all default to nil)" do
      err = described_class.new("no context")
      expect(err.endpoint).to be_nil
      expect(err.status).to   be_nil
    end
  end

  describe "hierarchy" do
    {
      Contractkit::NotFoundError => described_class,
      Contractkit::AuthenticationError => described_class,
      Contractkit::ServerError => described_class,
      Contractkit::MalformedResponseError => described_class,
      Contractkit::ConfigurationError => described_class,
      Contractkit::RateLimitError => described_class,
      Contractkit::Sam::NotFoundError => Contractkit::NotFoundError,
      Contractkit::Sam::AuthenticationError => Contractkit::AuthenticationError,
      Contractkit::Sam::ServerError => Contractkit::ServerError,
      Contractkit::Sam::MalformedResponseError => Contractkit::MalformedResponseError,
      Contractkit::Sam::RateLimitError => Contractkit::RateLimitError,
      Contractkit::Usaspending::NotFoundError => Contractkit::NotFoundError,
      Contractkit::Usaspending::ServerError => Contractkit::ServerError,
      Contractkit::Usaspending::MalformedResponseError => Contractkit::MalformedResponseError,
      Contractkit::Usaspending::RateLimitError => Contractkit::RateLimitError
    }.each do |klass, parent|
      it "#{klass.name} < #{parent.name}" do
        expect(klass.ancestors).to include(parent, described_class, StandardError)
      end
    end

    it "USASpending does NOT define AuthenticationError (API is keyless)" do
      expect(Contractkit::Usaspending.const_defined?(:AuthenticationError)).to be(false)
    end

    it "`rescue Contractkit::Error` catches every gem error" do
      gem_errors = [
        described_class.new,
        Contractkit::NotFoundError.new,
        Contractkit::RateLimitError.new,
        Contractkit::Sam::AuthenticationError.new,
        Contractkit::Usaspending::ServerError.new
      ]
      expect(gem_errors).to all(be_a(described_class))
    end

    it "`rescue Contractkit::RateLimitError` catches per-API rate limits" do
      sam = Contractkit::Sam::RateLimitError.new
      usa = Contractkit::Usaspending::RateLimitError.new
      expect(sam).to be_a(Contractkit::RateLimitError)
      expect(usa).to be_a(Contractkit::RateLimitError)
    end
  end

  describe Contractkit::RateLimitError do
    it "exposes retry_after" do
      err = described_class.new("slow down", retry_after: 30, status: 429)
      expect(err.retry_after).to eq(30)
      expect(err.status).to      eq(429)
    end

    it "treats retry_after as nil when not provided" do
      expect(described_class.new("slow down").retry_after).to be_nil
    end

    it "is rescue-compatible with the per-API subclasses (carries retry_after through)" do
      err = Contractkit::Sam::RateLimitError.new("slow", retry_after: 60)
      expect(err).to be_a(described_class)
      expect(err.retry_after).to eq(60)
    end
  end
end
