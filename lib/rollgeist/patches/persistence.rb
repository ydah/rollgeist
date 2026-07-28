# frozen_string_literal: true

module Rollgeist
  module Patches
    module Persistence
      def reload(...)
        result = super
        Rollgeist.clear_mark!(self)
        result
      end

      def destroy(...)
        return super unless defined?(@__rollgeist_mark)

        Rollgeist::Notifier.notify(self, :resave)
        mark = instance_variable_get(MARK_IVAR)
        reported = instance_variable_get(REPORTED_IVAR) if instance_variable_defined?(REPORTED_IVAR)
        Rollgeist.clear_mark!(self)
        result = super
        restore_mark(mark, reported) unless result
        result
      rescue Exception # rubocop:disable Lint/RescueException
        restore_mark(mark, reported) if mark && !frozen?
        raise
      end

      private

      def create_or_update(...)
        if defined?(@__rollgeist_mark)
          Rollgeist::Notifier.notify(self, :resave)
        end

        result = super
        if result
          Rollgeist.clear_mark!(self)
          Rollgeist.mark_saved!(self)
        end
        result
      end

      def restore_mark(mark, reported)
        instance_variable_set(MARK_IVAR, mark)
        instance_variable_set(REPORTED_IVAR, reported) if reported
        Rollgeist::RecordWatchpoints.install!(self)
      rescue StandardError => error
        Rollgeist.tracking_failure("mark restoration", error)
      end
    end
  end
end
