# frozen_string_literal: true

module Rollgeist
  class Report
    attr_reader :access_location,
      :accessed_at,
      :action,
      :changed_attributes,
      :model_name,
      :record_id,
      :rollback_location,
      :rolled_back_at,
      :values,
      :watchpoint

    def self.build(record:, mark:, watchpoint:)
      changed_attributes = mark.changed_attributes
      values = changed_attributes.to_h do |attribute|
        [attribute, safely_read(record, attribute)]
      end

      new(
        access_location: Rollgeist.capture_location,
        accessed_at: Time.now,
        action: mark.action,
        changed_attributes: changed_attributes,
        model_name: record.class.name || record.class.to_s,
        record_id: record.id,
        rollback_location: mark.rollback_location,
        rolled_back_at: mark.rolled_back_at,
        values: values,
        watchpoint: watchpoint
      )
    end

    def self.safely_read(record, attribute)
      record.read_attribute_for_serialization(attribute)
    rescue StandardError => error
      "<unavailable: #{error.class}>"
    end
    private_class_method :safely_read

    def initialize(
      access_location:,
      accessed_at:,
      action:,
      changed_attributes:,
      model_name:,
      record_id:,
      rollback_location:,
      rolled_back_at:,
      values:,
      watchpoint:
    )
      @access_location = access_location
      @accessed_at = accessed_at
      @action = action
      @changed_attributes = changed_attributes
      @model_name = model_name
      @record_id = record_id
      @rollback_location = rollback_location
      @rolled_back_at = rolled_back_at
      @values = values
      @watchpoint = watchpoint
      freeze
    end

    def to_h
      {
        access_location: access_location,
        accessed_at: accessed_at,
        action: action,
        changed_attributes: changed_attributes,
        model_name: model_name,
        record_id: record_id,
        rollback_location: rollback_location,
        rolled_back_at: rolled_back_at,
        values: values,
        watchpoint: watchpoint
      }
    end

    def to_s
      Formatter.new(self).to_s
    end
  end
end
