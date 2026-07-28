# frozen_string_literal: true

RSpec.describe "reporting controls" do
  it "publishes the documented notification event" do
    reports = []
    subscriber = ActiveSupport::Notifications.subscribe(
      Rollgeist::Notifier::EVENT_NAME
    ) do |*arguments|
      reports << ActiveSupport::Notifications::Event.new(*arguments).payload.fetch(:report)
    end
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    record.as_json

    expect(reports.one?).to be(true)
    expect(reports.first.model_name).to eq("GuardedRecord")
    expect(reports.first.changed_attributes).to include("name")
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it "filters reports with ignore_if" do
    seen_report = nil
    configure_guard do |configuration|
      configuration.ignore_if = lambda do |report|
        seen_report = report
        report.model_name == "GuardedRecord"
      end
    end
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    record.as_json

    expect(seen_report.values.fetch("name")).to eq("after")
    expect(guard_logger.warnings).to be_empty
  end

  it "keeps serialization behavior when a notification subscriber fails" do
    subscriber = ActiveSupport::Notifications.subscribe(
      Rollgeist::Notifier::EVENT_NAME
    ) { raise "subscriber failed" }
    record = rolled_back_update(GuardedRecord.create!(name: "before"))
    expected = Rollgeist.suppress { record.as_json }
    result = nil

    expect { result = record.as_json }
      .to output(/notification failure: RuntimeError: subscriber failed/).to_stderr
    expect(result).to eq(expected)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it "keeps serialization behavior when the configured logger fails" do
    failing_logger = Object.new
    def failing_logger.warn(_message)
      raise "logger failed"
    end
    configure_guard { |configuration| configuration.logger = failing_logger }
    record = rolled_back_update(GuardedRecord.create!(name: "before"))
    expected = Rollgeist.suppress { record.as_json }
    result = nil

    expect { result = record.as_json }
      .to output(/logger failure: RuntimeError: logger failed/).to_stderr
    expect(result).to eq(expected)
  end

  it "limits a bulk request and emits a suppression summary" do
    records = Array.new(100) { GuardedRecord.create!(name: "before") }
    ActiveRecord::Base.transaction do
      records.each { |record| record.update!(name: "after") }
      raise ActiveRecord::Rollback
    end
    ActiveSupport::Executor.wrap { records.each(&:as_json) }

    reports = guard_logger.warnings.grep(/Rollgeist::GhostRecordAccess/)
    summaries = guard_logger.warnings.grep(/\+95 more suppressed/)
    expect(reports.size).to eq(5)
    expect(summaries.size).to eq(1)
  end

  it "resets the report limit for the next execution" do
    configure_guard { |configuration| configuration.max_reports_per_request = 1 }
    records = Array.new(2) do
      rolled_back_update(GuardedRecord.create!(name: "before"))
    end

    ActiveSupport::Executor.wrap { records.first.as_json }
    ActiveSupport::Executor.wrap { records.last.as_json }

    expect(guard_logger.warnings.grep(/GhostRecordAccess/).size).to eq(2)
  end
end
