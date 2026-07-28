# frozen_string_literal: true

RSpec.describe "rollback marking" do
  it "marks an updated record after rollback and preserves its in-memory value" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))
    mark = Rollgeist.mark_for(record)

    expect(mark.action).to eq(:update)
    expect(mark.changed_attributes).to include("name")
    expect(record.name).to eq("after")
    expect(record.reload.name).to eq("before")
  end

  it "marks a created record after Rails restores its new-record state" do
    record = nil

    ActiveRecord::Base.transaction do
      record = GuardedRecord.create!(name: "created")
      raise ActiveRecord::Rollback
    end

    expect(Rollgeist.mark_for(record).action).to eq(:create)
    expect(record).to be_new_record
    expect(record.id).to be_nil
    expect(record.name).to eq("created")
  end

  it "marks a record rolled back to a savepoint after the outer commit" do
    record = GuardedRecord.create!(name: "before")

    ActiveRecord::Base.transaction do
      ActiveRecord::Base.transaction(requires_new: true) do
        record.update!(name: "after")
        raise ActiveRecord::Rollback
      end
    end

    expect(Rollgeist.mark_for(record)).not_to be_nil
    expect(record.name).to eq("after")
    expect(record.reload.name).to eq("before")
  end

  it "does not mark a joined nested rollback because no database rollback occurs" do
    record = GuardedRecord.create!(name: "before")

    ActiveRecord::Base.transaction do
      ActiveRecord::Base.transaction do
        record.update!(name: "after")
        raise ActiveRecord::Rollback
      end
    end

    expect(Rollgeist.mark_for(record)).to be_nil
    expect(record.reload.name).to eq("after")
  end

  it "documents update_columns as an undetected write path" do
    record = GuardedRecord.create!(name: "before")

    ActiveRecord::Base.transaction do
      record.update_columns(name: "after")
      raise ActiveRecord::Rollback
    end

    expect(Rollgeist.mark_for(record)).to be_nil
    expect(record.name).to eq("after")
    expect(record.reload.name).to eq("before")
  end

  it "deliberately excludes touch-only rollbacks" do
    record = GuardedRecord.create!(name: "before")

    ActiveRecord::Base.transaction do
      record.touch
      raise ActiveRecord::Rollback
    end

    expect(Rollgeist.mark_for(record)).to be_nil
  end

  it "attaches the mark after application after_rollback callbacks" do
    observed_mark = :not_called
    GuardedRecord.rollback_observer = lambda do |record|
      observed_mark = Rollgeist.mark_for(record)
    end

    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    expect(observed_mark).to be_nil
    expect(Rollgeist.mark_for(record)).not_to be_nil
  end

  it "marks a rolled-back destroy after Rails unfreezes the record" do
    record = GuardedRecord.create!(name: "before")

    ActiveRecord::Base.transaction do
      record.destroy!
      raise ActiveRecord::Rollback
    end

    expect(Rollgeist.mark_for(record).action).to eq(:destroy)
    expect(record).not_to be_destroyed
    expect(record).not_to be_frozen
  end

  it "does not retain marked records globally" do
    weak_record = build_collectable_ghost

    10.times do
      GC.start
      break unless weak_record.weakref_alive?
    end

    expect(weak_record).not_to be_weakref_alive
  end
end
