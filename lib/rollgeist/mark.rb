# frozen_string_literal: true

module Rollgeist
  class Mark
    ACTIONS = %i[create update destroy].freeze

    attr_reader :action, :changed_attributes, :rollback_location, :rolled_back_at

    def initialize(action:, changed_attributes:, rollback_location:, rolled_back_at:)
      raise ArgumentError, "unsupported rollback action: #{action}" unless ACTIONS.include?(action)

      @action = action
      @changed_attributes = changed_attributes.map(&:to_s).uniq.freeze
      @rollback_location = rollback_location
      @rolled_back_at = rolled_back_at
      freeze
    end
  end
end
