# frozen_string_literal: true

module Rollgeist
  class Formatter
    ACCESS_DESCRIPTIONS = {
      global_id: "was converted to a GlobalID",
      resave: "was saved or destroyed again",
      serialization: "was serialized"
    }.freeze
    ACTION_DESCRIPTIONS = {
      create: "creation",
      destroy: "destruction",
      update: "update"
    }.freeze

    def initialize(report)
      @report = report
    end

    def to_s
      <<~MESSAGE.chomp
        Rollgeist::GhostRecordAccess

        #{record_label} #{ACCESS_DESCRIPTIONS.fetch(report.watchpoint)} after its #{ACTION_DESCRIPTIONS.fetch(report.action)} was rolled back.

        The in-memory object still carries:
        #{formatted_values}

        Rolled back at:
          #{report.rollback_location || "(location unavailable)"}  (#{formatted_age} ago)

        Accessed at:
          #{report.access_location || "(location unavailable)"}

        Call `record.reload` before using this object,
        or move the usage inside the transaction.
      MESSAGE
    end

    private

    attr_reader :report

    def record_label
      identifier = report.record_id.nil? ? "new" : report.record_id
      "#{report.model_name}##{identifier}"
    end

    def formatted_values
      return "  (no attribute changes captured)" if report.values.empty?

      report.values.map do |attribute, value|
        "  #{attribute}: #{value.inspect}        (database: rolled back)"
      end.join("\n")
    end

    def formatted_age
      seconds = report.accessed_at - report.rolled_back_at
      format("%.1fs", [seconds, 0].max)
    end
  end
end
