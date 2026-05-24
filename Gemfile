# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  gem "rake", "~> 13.0"
  gem "rubocop", "~> 1.0", require: false
  gem "rubocop-performance", "~> 1.0", require: false
  gem "rubocop-rspec", "~> 3.0", require: false
end

group :test do
  gem "activesupport", "~> 7.0", require: false # for testing the AS::Notifications integration path
  gem "rspec", "~> 3.0"
  gem "vcr", "~> 6.0"
  gem "webmock", "~> 3.18"
end
