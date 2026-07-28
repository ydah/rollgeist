# frozen_string_literal: true

require "active_support"
require "active_support/executor"
require "active_support/isolated_execution_state"
require "active_support/lazy_load_hooks"
require "active_support/notifications"

require_relative "rollgeist/version"
require_relative "rollgeist/configuration"
require_relative "rollgeist/errors"
require_relative "rollgeist/execution_state"
require_relative "rollgeist/formatter"
require_relative "rollgeist/mark"
require_relative "rollgeist/notifier"
require_relative "rollgeist/report"
require_relative "rollgeist/patches/global_id"
require_relative "rollgeist/patches/persistence"
require_relative "rollgeist/patches/serialization"
require_relative "rollgeist/patches/transactions"

module Rollgeist
  MARK_IVAR = :@__rollgeist_mark
  REPORTED_IVAR = :@__rollgeist_reported
  SAVED_IVAR = :@__rollgeist_saved
  SUPPRESSION_KEY = :__rollgeist_suppression_depth

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration.validate!
      install_global_id_patch!
      configuration
    end

    def reset!
      @configuration = Configuration.new
      ExecutionState.reset!
    end

    def environment
      return Rails.env.to_s if defined?(Rails) && Rails.respond_to?(:env)

      ENV.fetch("RAILS_ENV", ENV.fetch("RACK_ENV", "development"))
    end

    def enabled?
      configuration.enabled_in?(environment)
    end

    def suppress
      previous_depth = ActiveSupport::IsolatedExecutionState[SUPPRESSION_KEY]
      ActiveSupport::IsolatedExecutionState[SUPPRESSION_KEY] = previous_depth.to_i + 1
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[SUPPRESSION_KEY] = previous_depth
    end

    def suppressed?
      ActiveSupport::IsolatedExecutionState[SUPPRESSION_KEY].to_i.positive?
    end

    def install!(active_record_base)
      active_record_base.prepend(Patches::Transactions) unless active_record_base < Patches::Transactions
      active_record_base.prepend(Patches::Persistence) unless active_record_base < Patches::Persistence
      active_record_base.prepend(Patches::Serialization) unless active_record_base < Patches::Serialization
      install_global_id_patch!
      ExecutionState.install!
    end

    def install_global_id_patch!
      return unless defined?(GlobalID::Identification)
      return if GlobalID::Identification < Patches::GlobalId

      GlobalID::Identification.prepend(Patches::GlobalId)
    end

    def mark_for(record)
      record.instance_variable_get(MARK_IVAR)
    end

    def mark_saved!(record)
      record.instance_variable_set(SAVED_IVAR, true) if enabled?
    rescue StandardError => error
      tracking_failure("save tracking", error)
    end

    def rollback_snapshot(record)
      return unless enabled?

      action = rollback_action(record)
      return unless action

      {
        action: action,
        changed_attributes: rollback_changed_attributes(record, action),
        rolled_back_at: Time.now,
        rollback_location: capture_location
      }
    rescue StandardError => error
      tracking_failure("rollback snapshot", error)
      nil
    end

    def attach_mark!(record, attributes)
      record.instance_variable_set(MARK_IVAR, Mark.new(**attributes))
      remove_ivar(record, REPORTED_IVAR)
      clear_transaction_write_state!(record)
    rescue StandardError => error
      tracking_failure("mark attachment", error)
    end

    def clear_mark!(record)
      remove_ivar(record, MARK_IVAR)
      remove_ivar(record, REPORTED_IVAR)
    rescue StandardError => error
      tracking_failure("mark cleanup", error)
    end

    def clear_record_state!(record)
      clear_mark!(record)
      clear_transaction_write_state!(record)
    end

    def clear_transaction_write_state!(record)
      remove_ivar(record, SAVED_IVAR)
    rescue StandardError => error
      tracking_failure("transaction-state cleanup", error)
    end

    def capture_location
      location = caller_locations(2, 50).find do |candidate|
        application_location?(candidate.path)
      end
      location && "#{location.path}:#{location.lineno}"
    end

    def tracking_failure(context, error)
      Kernel.warn("Rollgeist #{context} failure: #{error.class}: #{error.message}")
    rescue StandardError
      nil
    end

    private

    def rollback_action(record)
      return :destroy if record.destroyed?
      return unless record.instance_variable_defined?(SAVED_IVAR)

      record.previously_new_record? ? :create : :update
    end

    def rollback_changed_attributes(record, action)
      attributes = if action == :destroy
        record.changes_to_save.keys
      else
        record.saved_changes.keys
      end

      attributes.map(&:to_s).uniq
    end

    def application_location?(path)
      return false unless path
      return false if path.start_with?(__dir__)
      return false if path.include?("/active_record/")
      return false if path.include?("/active_support/")

      true
    end

    def remove_ivar(record, ivar)
      return unless record.instance_variable_defined?(ivar)

      record.remove_instance_variable(ivar)
    end
  end
end

begin
  require "global_id"
rescue LoadError
  nil
end

ActiveSupport.on_load(:active_record) do
  Rollgeist.install!(self)
end

begin
  require "rails/railtie"
rescue LoadError
  nil
end

require_relative "rollgeist/railtie" if defined?(Rails::Railtie)
