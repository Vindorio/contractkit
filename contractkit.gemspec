# frozen_string_literal: true

require_relative "lib/contractkit/version"

Gem::Specification.new do |spec|
  spec.name        = "contractkit"
  spec.version     = Contractkit::VERSION
  spec.authors     = ["Charles Gude"]
  spec.email       = ["gudetimes1234@gmail.com"]

  spec.summary     = "Federal procurement data for Ruby (SAM.gov + USASpending.gov)"
  spec.description = <<~DESC
    contractkit aggregates federal contract opportunities (SAM.gov) and
    historical award data (USASpending.gov) into a single, framework-agnostic
    Ruby library. Handles authentication, pagination, rate limiting, retries,
    typed model objects, agency normalization, and cross-referencing
    opportunities to related past awards.
  DESC

  spec.homepage    = "https://github.com/Vindorio/contractkit"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  # NOTE: homepage_uri is derived from spec.homepage automatically; don't
  # set it explicitly to avoid the rubygems duplicate-key warning.
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Only allow pushes to rubygems.org. The release workflow (OIDC
  # trusted publishing) ignores this; setting it explicitly prevents
  # an accidental `gem push` against a private gem server from a dev
  # machine.
  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  # Documentation URI — used by RubyGems's project page.
  spec.metadata["documentation_uri"] = "#{spec.homepage}/blob/main/README.md"

  spec.files = Dir[
    "lib/**/*",
    "CHANGELOG.md",
    "LICENSE*",
    "README.md",
    "contractkit.gemspec"
  ]
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
end
