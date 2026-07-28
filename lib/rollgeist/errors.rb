# frozen_string_literal: true

module Rollgeist
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class GhostRecordAccess < Error
    attr_reader :report

    def initialize(report)
      @report = report
      super(report.to_s)
    end
  end
end
