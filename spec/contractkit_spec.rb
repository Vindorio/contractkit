# frozen_string_literal: true

RSpec.describe Contractkit do
  it "has a version number" do
    expect(Contractkit::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
