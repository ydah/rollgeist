# frozen_string_literal: true

RSpec.describe Rollgeist::Configuration do
  it "has the documented defaults" do
    configuration = described_class.new

    expect(configuration.warn_on_serialization).to be(true)
    expect(configuration.warn_on_global_id).to be(true)
    expect(configuration.warn_on_resave).to be(false)
    expect(configuration.warn_once).to be(true)
    expect(configuration.max_reports_per_request).to eq(5)
    expect(configuration.enabled_environments).to eq(%w[development test])
  end

  it "rejects an invalid mode" do
    expect do
      Rollgeist.configure { |configuration| configuration.mode = :ignore }
    end.to raise_error(Rollgeist::ConfigurationError, /mode/)
  end

  it "rejects a non-positive report limit" do
    expect do
      Rollgeist.configure do |configuration|
        configuration.max_reports_per_request = 0
      end
    end.to raise_error(Rollgeist::ConfigurationError, /positive Integer/)
  end

  it "rejects a non-callable ignore predicate" do
    expect do
      Rollgeist.configure { |configuration| configuration.ignore_if = true }
    end.to raise_error(Rollgeist::ConfigurationError, /callable/)
  end

  it "rejects raise mode outside the test environment" do
    allow(Rollgeist).to receive(:environment).and_return("development")

    expect do
      Rollgeist.configure { |configuration| configuration.mode = :raise }
    end.to raise_error(Rollgeist::ConfigurationError, /test environment/)
  end

  it "is disabled in production unless explicitly enabled" do
    configuration = described_class.new

    expect(configuration.enabled_in?("production")).to be(false)
    configuration.enabled_environments << "production"
    expect(configuration.enabled_in?("production")).to be(true)
  end
end
