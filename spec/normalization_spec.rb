# frozen_string_literal: true

RSpec.describe "ghost normalization" do
  it "clears a mark after reload" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    record.reload

    expect(Rollgeist.mark_for(record)).to be_nil
    expect(record.name).to eq("before")
    record.as_json
    expect(guard_logger.warnings).to be_empty
  end

  it "clears a mark after a successful save" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    expect(record.save!).to be(true)

    expect(Rollgeist.mark_for(record)).to be_nil
    expect(record.reload.name).to eq("after")
    record.as_json
    expect(guard_logger.warnings).to be_empty
  end

  it "clears a mark after a successful destroy" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    expect(record.destroy!).to eq(record)

    expect(Rollgeist.mark_for(record)).to be_nil
    expect(record).to be_destroyed
  end

  it "keeps a mark when a resave fails validation" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))
    record.name = nil

    expect(record.save).to be(false)
    expect(Rollgeist.mark_for(record)).not_to be_nil
  end

  it "refreshes a mark when a later save is rolled back" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))
    first_mark = Rollgeist.mark_for(record)

    ActiveRecord::Base.transaction do
      record.update!(name: "again")
      raise ActiveRecord::Rollback
    end

    second_mark = Rollgeist.mark_for(record)
    expect(second_mark).not_to equal(first_mark)
    expect(second_mark.changed_attributes).to include("name")
    expect(second_mark.rolled_back_at).to be >= first_mark.rolled_back_at
  end

  it "retains a mark when reload fails" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))
    GuardedRecord.where(id: record.id).delete_all

    expect { record.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Rollgeist.mark_for(record)).not_to be_nil
  end
end
