# frozen_string_literal: true

RSpec.describe Rollgeist do
  it "has a version number" do
    expect(described_class::VERSION).to eq("0.1.0")
  end

  it "uses environment-sensitive default modes" do
    configuration = Rollgeist::Configuration.new

    expect(configuration.mode).to eq(:raise)
  end

  it "can suppress reports for a block" do
    record = rolled_back_update(GuardedRecord.create!(name: "before"))

    result = described_class.suppress { record.as_json }

    expect(result.fetch("name")).to eq("after")
    expect(guard_logger.warnings).to be_empty
  end
end
