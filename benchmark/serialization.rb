# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "development"

if (version = ENV["ROLLGEIST_ACTIVE_RECORD_VERSION"])
  gem "activesupport", version
  gem "activerecord", version
end

require "active_record"
require "benchmark/ips"

BASE_SERIALIZABLE_HASH = ActiveRecord::Serialization.instance_method(:serializable_hash)

require "rollgeist"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :benchmark_records do |table|
    table.string :name, null: false
    table.string :status
    table.string :category
    table.string :description
    table.string :email
    table.string :locale
    table.string :region
    table.string :role
    table.string :slug
    table.string :time_zone
    table.integer :lock_version, null: false, default: 0
    table.timestamps null: false
  end
end

class GuardedBenchmarkRecord < ActiveRecord::Base
  self.table_name = "benchmark_records"
end

attributes = {
  category: "account",
  description: "Representative serialized record",
  email: "user@example.test",
  locale: "en",
  name: "example",
  region: "ap-northeast-1",
  role: "member",
  slug: "example",
  status: "active",
  time_zone: "Asia/Tokyo"
}
seed_record = GuardedBenchmarkRecord.create!(attributes)
baseline_record = GuardedBenchmarkRecord.find(seed_record.id)
guarded_record = GuardedBenchmarkRecord.find(seed_record.id)

unless guarded_record.method(:serializable_hash).owner == BASE_SERIALIZABLE_HASH.owner
  abort "unmarked serialization path differs from Active Record"
end

report = Benchmark.ips(time: 5, warmup: 2) do |benchmark|
  benchmark.report("baseline") { baseline_record.as_json }
  benchmark.report("guarded") { guarded_record.as_json }
  benchmark.compare!
end

entries = report.entries.to_h { |entry| [entry.label, entry] }
baseline_ips = entries.fetch("baseline").ips
guarded_ips = entries.fetch("guarded").ips
overhead = ((baseline_ips / guarded_ips) - 1) * 100

puts format(
  "Unmarked as_json overhead: %.2f%% (%s, Active Record %s, %d columns)",
  overhead,
  RUBY_DESCRIPTION,
  ActiveRecord.version,
  GuardedBenchmarkRecord.column_names.size
)
