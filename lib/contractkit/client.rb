# frozen_string_literal: true

module Contractkit
  # Instance-based entry point for multi-tenant consumers. Each Client
  # carries its own Configuration; two Client instances never share state
  # with each other or with the global Contractkit.configuration.
  #
  # For single-tenant scripts and most Rails apps, the global pattern is
  # simpler — use Contractkit.configure { |c| ... } and the resource
  # modules (Contractkit::Opportunity.search, etc., shipped in M2).
  class Client
    attr_reader :configuration

    def initialize(**)
      @configuration = Configuration.new(**)
    end

    # Sugar for in-place option mutation, mirroring Contractkit.configure
    # at the instance scope.
    def configure
      yield @configuration
      self
    end
  end
end
