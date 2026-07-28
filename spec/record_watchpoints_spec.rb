# frozen_string_literal: true

RSpec.describe Rollgeist::RecordWatchpoints do
  class UndestroyableGuardedRecord < GuardedRecord
    before_destroy { throw :abort }
  end

  it "does not alter serialization for a record that has never been marked" do
    record = GuardedRecord.create!(name: "before")

    expect(record.singleton_methods).not_to include(:serializable_hash, :to_global_id)
    expect(record.method(:serializable_hash).owner).not_to eq(record.singleton_class)
  end

  it "installs watchpoints only on a marked record" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    expect(record.singleton_methods).to include(:serializable_hash, :to_global_id)
    expect(record.method(:serializable_hash).owner).to eq(record.singleton_class)
  end

  it "removes watchpoints after reload normalizes the record" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    record.reload

    expect(record.singleton_methods).not_to include(:serializable_hash, :to_global_id)
    expect(record.method(:serializable_hash).owner).not_to eq(record.singleton_class)
  end

  it "removes watchpoints after a successful save" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    record.save!

    expect(record.singleton_methods).not_to include(:serializable_hash, :to_global_id)
  end

  it "removes watchpoints after a successful destroy" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    record.destroy!

    expect(record.singleton_methods).not_to include(:serializable_hash, :to_global_id)
  end

  it "restores watchpoints when destroy is aborted" do
    record = rolled_back_update(UndestroyableGuardedRecord.create!(name: "before"))

    expect(record.destroy).to be(false)
    expect(Rollgeist.mark_for(record)).not_to be_nil
    expect(record.singleton_methods).to include(:serializable_hash, :to_global_id)

    record.as_json
    expect(guard_logger.warnings.one?).to be(true)
  end

  it "preserves a pre-existing singleton serialization method" do
    record = GuardedRecord.create!(name: "before")
    record.define_singleton_method(:serializable_hash) do |options = nil|
      super(options).merge("singleton_value" => true)
    end

    rolled_back_update(record)
    expect(record.as_json.fetch("singleton_value")).to be(true)
    expect(guard_logger.warnings.one?).to be(true)

    record.reload
    guard_logger.warnings.clear

    expect(record.as_json.fetch("singleton_value")).to be(true)
    expect(record.method(:serializable_hash).owner).to eq(record.singleton_class)
    expect(guard_logger.warnings).to be_empty
  end
end
