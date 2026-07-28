# frozen_string_literal: true

module Rollgeist
  class Configuration
    MODES = %i[log raise].freeze

    attr_accessor :enabled_environments,
      :ignore_if,
      :logger,
      :max_reports_per_request,
      :warn_once,
      :warn_on_global_id,
      :warn_on_resave,
      :warn_on_serialization
    attr_writer :mode

    def initialize
      @enabled_environments = %w[development test]
      @ignore_if = nil
      @logger = nil
      @max_reports_per_request = 5
      @mode = nil
      @warn_once = true
      @warn_on_global_id = true
      @warn_on_resave = false
      @warn_on_serialization = true
    end

    def mode
      @mode || (Rollgeist.environment == "test" ? :raise : :log)
    end

    def enabled_in?(environment)
      enabled_environments.map(&:to_s).include?(environment.to_s)
    end

    def watchpoint_enabled?(watchpoint)
      case watchpoint
      when :serialization then warn_on_serialization
      when :global_id then warn_on_global_id
      when :resave then warn_on_resave
      else false
      end
    end

    def validate!
      validate_mode!
      validate_limit!
      validate_ignore_predicate!
      validate_environments!
      self
    end

    private

    def validate_mode!
      unless MODES.include?(mode)
        raise ConfigurationError, "mode must be one of: #{MODES.join(", ")}"
      end
      return unless mode == :raise && Rollgeist.environment != "test"

      raise ConfigurationError, "raise mode is only available in the test environment"
    end

    def validate_limit!
      return if max_reports_per_request.is_a?(Integer) && max_reports_per_request.positive?

      raise ConfigurationError, "max_reports_per_request must be a positive Integer"
    end

    def validate_ignore_predicate!
      return if ignore_if.nil? || ignore_if.respond_to?(:call)

      raise ConfigurationError, "ignore_if must be callable or nil"
    end

    def validate_environments!
      return if enabled_environments.is_a?(Array)

      raise ConfigurationError, "enabled_environments must be an Array"
    end
  end
end
