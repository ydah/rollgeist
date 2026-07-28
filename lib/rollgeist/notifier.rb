# frozen_string_literal: true

module Rollgeist
  module Notifier
    EVENT_NAME = "ghost_access.rollgeist"
    WATCHPOINT_BITS = {
      serialization: 1,
      global_id: 2,
      resave: 4
    }.freeze

    class << self
      def notify(record, watchpoint)
        return unless Rollgeist.enabled?
        return if Rollgeist.suppressed?

        configuration = Rollgeist.configuration
        return unless configuration.watchpoint_enabled?(watchpoint)

        mark = Rollgeist.mark_for(record)
        return unless mark

        report = Report.build(record: record, mark: mark, watchpoint: watchpoint)
        return if ignored?(configuration, report)
        return if configuration.warn_once && !claim_watchpoint(record, watchpoint)

        decision = ExecutionState.claim(configuration.max_reports_per_request)
        report_suppressed(decision.suppressed_to_flush) if decision.suppressed_to_flush
        return unless decision.allowed

        emit(report, configuration)
      rescue GhostRecordAccess
        raise
      rescue StandardError => error
        warn_safely("Rollgeist notifier failure: #{error.class}: #{error.message}")
      end

      def report_suppressed(count)
        return unless count.to_i.positive?

        log_safely("Rollgeist: +#{count} more suppressed")
      end

      private

      def ignored?(configuration, report)
        configuration.ignore_if&.call(report)
      rescue StandardError => error
        warn_safely("Rollgeist ignore_if failure: #{error.class}: #{error.message}")
        false
      end

      def claim_watchpoint(record, watchpoint)
        bit = WATCHPOINT_BITS.fetch(watchpoint)
        reported = if record.instance_variable_defined?(REPORTED_IVAR)
          record.instance_variable_get(REPORTED_IVAR)
        else
          0
        end
        return false unless (reported & bit).zero?

        record.instance_variable_set(REPORTED_IVAR, reported | bit)
        true
      end

      def emit(report, configuration)
        instrument_safely(report)

        if configuration.mode == :raise
          raise GhostRecordAccess, report
        end

        log_safely(report.to_s)
      end

      def instrument_safely(report)
        ActiveSupport::Notifications.instrument(EVENT_NAME, report: report)
      rescue StandardError => error
        warn_safely("Rollgeist notification failure: #{error.class}: #{error.message}")
      end

      def log_safely(message)
        logger = Rollgeist.configuration.logger
        logger ||= Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)
        logger ? logger.warn(message) : Kernel.warn(message)
      rescue StandardError => error
        warn_safely("Rollgeist logger failure: #{error.class}: #{error.message}")
      end

      def warn_safely(message)
        Kernel.warn(message)
      rescue StandardError
        nil
      end
    end
  end
end
