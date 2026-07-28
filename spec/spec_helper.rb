# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require "active_record"
require "global_id"
require "stringio"
require "weakref"
require "rollgeist"

GlobalID.app = "rollgeist"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :guarded_records do |table|
    table.string :name, null: false
    table.string :status
    table.timestamps null: false
  end
end

class GuardedRecord < ActiveRecord::Base
  include GlobalID::Identification
  validates :name, presence: true

  class << self
    attr_accessor :rollback_observer
  end

  after_rollback do
    self.class.rollback_observer&.call(self)
  end
end

class RecordingLogger
  attr_reader :warnings

  def initialize
    @warnings = []
  end

  def warn(message)
    warnings << message
  end
end

module SpecSupport
  def guard_logger
    @guard_logger
  end

  def configure_guard
    Rollgeist.configure do |configuration|
      yield(configuration) if block_given?
    end
  end

  def rolled_back_update(record, attributes = { name: "after" })
    ActiveRecord::Base.transaction do
      record.update!(attributes)
      raise ActiveRecord::Rollback
    end
    record
  end

  def build_collectable_ghost
    record = rolled_back_update(GuardedRecord.create!(name: "before"))
    WeakRef.new(record)
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.include SpecSupport

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.before do
    Rollgeist.reset!
    @guard_logger = RecordingLogger.new
    configure_guard do |configuration|
      configuration.logger = @guard_logger
      configuration.mode = :log
    end
    GuardedRecord.rollback_observer = nil
    GuardedRecord.delete_all
  end

  config.after do
    Rollgeist::ExecutionState.reset!
    GuardedRecord.rollback_observer = nil
  end
end
