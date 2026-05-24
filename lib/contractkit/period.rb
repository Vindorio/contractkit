# frozen_string_literal: true

require "date"

module Contractkit
  # Period of performance value object. start_date and end_date are
  # Ruby Date (not DateTime) — contract periods are calendar days, not
  # timestamps.
  class Period
    attr_reader :start_date, :end_date

    def initialize(start_date: nil, end_date: nil)
      @start_date = parse(start_date)
      @end_date   = parse(end_date)
      freeze
    end

    # @return [Hash] flat hash of start/end dates.
    def to_h
      { start_date: start_date, end_date: end_date }
    end

    # Value-equality by both start_date and end_date.
    def ==(other)
      other.is_a?(Period) && to_h == other.to_h
    end
    alias eql? ==

    # @return [Integer] hash code matching the equality contract.
    def hash
      to_h.hash
    end

    private

    def parse(value)
      return value if value.is_a?(Date) && !value.is_a?(DateTime)
      return nil if value.nil? || value.to_s.strip.empty?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
