# frozen_string_literal: true

RSpec.describe "ghost watchpoints" do
  it "reports as_json and preserves the original return value" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))
    expected = Rollgeist.suppress { record.as_json }

    result = record.as_json

    expect(result).to eq(expected)
    expect(guard_logger.warnings.one?).to be(true)
    expect(guard_logger.warnings.first).to include("was serialized")
  end

  it "reports direct serializable_hash calls" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    expect(record.serializable_hash.fetch("name")).to eq("after")
    expect(guard_logger.warnings.one?).to be(true)
  end

  it "raises a report in raise mode" do
    configure_guard { |configuration| configuration.mode = :raise }
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    expect { record.as_json }
      .to raise_error(Rollgeist::GhostRecordAccess, /GuardedRecord/)
  end

  it "reports GlobalID conversion and preserves its value" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))
    expected = Rollgeist.suppress { record.to_global_id }

    result = record.to_global_id

    expect(result).to eq(expected)
    expect(guard_logger.warnings.one?).to be(true)
    expect(guard_logger.warnings.first).to include("GlobalID")
  end

  it "warns once per instance and watchpoint" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    2.times { record.as_json }
    2.times { record.to_global_id }

    expect(guard_logger.warnings.size).to eq(2)
  end

  it "can report every repeated access when warn_once is disabled" do
    configure_guard { |configuration| configuration.warn_once = false }
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    2.times { record.as_json }

    expect(guard_logger.warnings.size).to eq(2)
  end

  it "does not report resaves by default and still clears the mark" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    record.save!

    expect(guard_logger.warnings).to be_empty
    expect(Rollgeist.mark_for(record)).to be_nil
  end

  it "reports a resave when explicitly enabled" do
    configure_guard { |configuration| configuration.warn_on_resave = true }
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    record.save!

    expect(guard_logger.warnings.one?).to be(true)
    expect(guard_logger.warnings.first).to include("saved or destroyed again")
  end

  it "does not warn for the default rollback-retry-save pattern" do
    record = GuardedRecord.create!(name: "before")
    attempts = 0

    begin
      ActiveRecord::Base.transaction do
        record.update!(name: "after")
        attempts += 1
        raise ActiveRecord::SerializationFailure if attempts == 1
      end
    rescue ActiveRecord::SerializationFailure
      retry
    end

    expect(guard_logger.warnings).to be_empty
    expect(Rollgeist.mark_for(record)).to be_nil
    expect(record.reload.name).to eq("after")
  end

  it "reports rollback-retry-save when resave reporting is enabled" do
    configure_guard { |configuration| configuration.warn_on_resave = true }
    record = GuardedRecord.create!(name: "before")
    attempts = 0

    begin
      ActiveRecord::Base.transaction do
        record.update!(name: "after")
        attempts += 1
        raise ActiveRecord::SerializationFailure if attempts == 1
      end
    rescue ActiveRecord::SerializationFailure
      retry
    end

    expect(guard_logger.warnings.size).to eq(1)
    expect(record.reload.name).to eq("after")
  end
end
