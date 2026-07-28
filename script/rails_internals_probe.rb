# frozen_string_literal: true

require "active_record"
require "json"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :probe_records do |table|
    table.string :name, null: false
    table.timestamps null: false
  end
end

module RailsInternalsProbe
  class << self
    attr_accessor :operation

    def events
      @events ||= []
    end

    def record(event, details = {})
      events << { event: event, operation: operation }.merge(details)
    end

    def capture(label)
      self.events = []
      yield
      { label: label, events: events }
    rescue StandardError => error
      { label: label, raised: error.class.name, events: events }
    ensure
      self.operation = nil
    end

    private

    attr_writer :events
  end

  module TransactionInstrumentation
    def add_to_transaction(...)
      RailsInternalsProbe.record(:add_to_transaction)
      super
    end

    def committed!(*args, **kwargs)
      RailsInternalsProbe.record(
        :committed,
        args: args,
        kwargs: kwargs,
        new_record: new_record?,
        destroyed: destroyed?,
        frozen: frozen?
      )
      super
    end

    def rolledback!(*args, **kwargs)
      before = {
        args: args,
        kwargs: kwargs,
        new_record: new_record?,
        id: id,
        destroyed: destroyed?,
        frozen: frozen?,
        name: self[:name],
        saved_changes: saved_changes.keys,
        pending_changes: changes_to_save.keys
      }
      result = super
      RailsInternalsProbe.record(
        :rolled_back,
        before: before,
        after: {
          new_record: new_record?,
          id: id,
          destroyed: destroyed?,
          frozen: frozen?,
          name: self[:name]
        }
      )
      result
    end
  end
end

ActiveRecord::Base.prepend(RailsInternalsProbe::TransactionInstrumentation)

class ProbeRecord < ActiveRecord::Base
  after_rollback do
    RailsInternalsProbe.record(
      :after_rollback,
      new_record: new_record?,
      destroyed: destroyed?,
      frozen: frozen?,
      name: name
    )
  end
end

def persisted_record
  ProbeRecord.create!(name: "before").tap { RailsInternalsProbe.events.clear }
end

results = []

results << RailsInternalsProbe.capture("active_record_rollback_update") do
  record = persisted_record
  ActiveRecord::Base.transaction do
    RailsInternalsProbe.operation = :save
    record.update!(name: "after")
    raise ActiveRecord::Rollback
  end
end

results << RailsInternalsProbe.capture("exception_update") do
  record = persisted_record
  ActiveRecord::Base.transaction do
    RailsInternalsProbe.operation = :save
    record.update!(name: "after")
    raise "failure"
  end
end

results << RailsInternalsProbe.capture("create_rollback") do
  record = nil
  ActiveRecord::Base.transaction do
    RailsInternalsProbe.operation = :save
    record = ProbeRecord.create!(name: "created")
    raise ActiveRecord::Rollback
  end
end

results << RailsInternalsProbe.capture("destroy_rollback") do
  record = persisted_record
  ActiveRecord::Base.transaction do
    RailsInternalsProbe.operation = :destroy
    record.destroy!
    raise ActiveRecord::Rollback
  end
end

results << RailsInternalsProbe.capture("savepoint_rollback_then_outer_commit") do
  record = persisted_record
  ActiveRecord::Base.transaction do
    ActiveRecord::Base.transaction(requires_new: true) do
      RailsInternalsProbe.operation = :savepoint_save
      record.update!(name: "after")
      raise ActiveRecord::Rollback
    end
    RailsInternalsProbe.operation = :outer_commit
  end
end

results << RailsInternalsProbe.capture("joined_nested_rollback") do
  record = persisted_record
  ActiveRecord::Base.transaction do
    ActiveRecord::Base.transaction do
      RailsInternalsProbe.operation = :joined_save
      record.update!(name: "after")
      raise ActiveRecord::Rollback
    end
    RailsInternalsProbe.operation = :outer_commit
  end
end

results << RailsInternalsProbe.capture("update_columns_rollback") do
  record = persisted_record
  ActiveRecord::Base.transaction do
    RailsInternalsProbe.operation = :update_columns
    record.update_columns(name: "after")
    raise ActiveRecord::Rollback
  end
end

results << RailsInternalsProbe.capture("touch_rollback") do
  record = persisted_record
  ActiveRecord::Base.transaction do
    RailsInternalsProbe.operation = :touch
    record.touch
    raise ActiveRecord::Rollback
  end
end

puts JSON.pretty_generate(
  active_record: ActiveRecord.version.to_s,
  ruby: RUBY_VERSION,
  results: results
)
