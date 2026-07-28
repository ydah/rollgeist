# Rollgeist

Rollgeist detects Active Record objects whose database writes were
rolled back while their in-memory attributes remained changed.

```ruby
user = User.find(1) # plan: "free"

ActiveRecord::Base.transaction do
  user.update!(plan: "premium")
  charge!(user) # raises; the transaction rolls back
rescue ChargeError
  nil
end

# The database still says "free", but this object says "premium".
NotificationMailer.upgraded(user).deliver_later if user.plan == "premium"
```

The gem marks records after Rails finishes `rolledback!`, then reports risky
externalization through `as_json`, `serializable_hash`, and `to_global_id`.
It does not restore attributes or change Rails transaction behavior.

## Installation

Add the gem to the application:

```ruby
gem "rollgeist", "~> 0.1.0"
```

Then run `bundle install`.

Rollgeist requires Ruby 3.2 or newer and Active Record 7.1 or newer.

## Configuration

Create `config/initializers/rollgeist.rb`:

```ruby
Rollgeist.configure do |config|
  # Defaults to :raise in test and :log elsewhere.
  # :raise is intentionally restricted to the test environment.
  config.mode = :log

  config.warn_on_serialization = true
  config.warn_on_global_id = true
  config.warn_on_resave = false
  config.warn_once = true
  config.max_reports_per_request = 5
  config.ignore_if = nil
  config.enabled_environments = %w[development test]
end
```

Production is disabled by default because serialization is a hot path and the
gem prepends behavior across all Active Record models. Enable it only after
observing the gem in development and test:

```ruby
config.enabled_environments = %w[development test production]
```

## What is reported

| Operation | Detected after rollback? | Notes |
|---|---:|---|
| Successful create/save | Yes | Includes exception-driven rollbacks |
| Successful update/save | Yes | In-memory changed values are reported |
| Destroy | Yes | Rails restores destroyed/frozen state first |
| `requires_new` savepoint | Yes | Mark survives the outer commit |
| Joined nested `ActiveRecord::Rollback` | No | No database rollback occurs |
| `update_columns` / `update_column` | No | No transaction record is registered |
| `touch` | No | Deliberately outside the 0.1 scope |
| `update_all`, `delete_all`, raw SQL | No | No model transaction record is registered |
| Ordinary attribute reads | No | Only externalization watchpoints are monitored |

This is a detector for specific unsafe paths, not a proof that an application
is free of rollback-related stale state.

## Clearing a mark

A mark is cleared when the object is known to agree with the database again:

```ruby
user.reload # clears after a successful reload
user.save!  # clears after a successful save
user.destroy! # clears after a successful destroy
```

A later rollback attaches a fresh mark. A successful `committed!` is also a
cleanup point.

## Resave reports are opt-in

`warn_on_resave` defaults to `false`. Rails calls `rolledback!` for deadlocks,
serialization failures, and other exception-driven rollbacks, so a legitimate
retry often looks like this:

```ruby
begin
  User.transaction { user.save! }
rescue ActiveRecord::SerializationFailure
  retry
end
```

The successful retry makes the database agree with the object. Reporting it by
default would be noisy and would flag a normal recovery pattern. Set
`warn_on_resave = true` only when that stricter signal is useful.

## Suppression and filtering

Suppress a known-safe block:

```ruby
Rollgeist.suppress do
  audit_payload = user.as_json
end
```

Or filter using the structured report:

```ruby
config.ignore_if = lambda do |report|
  report.model_name == "AuditSnapshot" ||
    report.changed_attributes.all? { |name| name == "updated_at" }
end
```

Reports are limited per Rails executor. At the default limit, a request that
would emit 100 reports logs five reports followed by:

```text
Rollgeist: +95 more suppressed
```

Outside an executor, a process-wide one-minute fallback window prevents
unbounded reporting.

## Notifications and reports

Every emitted report publishes `ghost_access.rollgeist` through
`ActiveSupport::Notifications`:

```ruby
ActiveSupport::Notifications.subscribe("ghost_access.rollgeist") do |event|
  report = event.payload.fetch(:report)
  ErrorTracker.notify(report.to_h)
end
```

Reports contain the model name, id, rollback action, changed attribute names
and in-memory values, rollback location, and access location. Subscriber,
filter, and logger failures are reduced to warnings and do not change the
serialization result. Only configured test `:raise` mode intentionally stops
the watched operation.

## Supported versions

| Active Record | Ruby 3.2 | Ruby 3.3 | Ruby 3.4 |
|---|---:|---:|---:|
| 7.1 | CI | CI | — |
| 7.2 | CI | CI | CI |
| 8.0 | CI | CI | CI |

Rails main runs in CI as an allowed-failure early-warning job because
`rolledback!`, `committed!`, and transaction-record registration are internal
APIs. See [the internal API probe](docs/rails_internals.md) for the fixed
behavioral assumptions.

## Performance

The unmarked serialization path performs one
`defined?(@__rollgeist_mark)` check before calling Rails.

A local sample on Ruby 4.0.0, Active Record 8.0.5, and a 14-column model
measured 152,531 baseline `as_json` calls/s and 135,523 guarded calls/s:
12.55% overhead. This misses the current +2% target, so applications should
remeasure on representative models and hardware before production opt-in.

Reproduce the benchmark with:

```sh
bundle exec appraisal rails_8_0 ruby -Ilib benchmark/serialization.rb
```

## Development

```sh
bundle install
bundle exec appraisal rails_7_1 rspec
bundle exec appraisal rails_7_2 rspec
bundle exec appraisal rails_8_0 rspec
gem build rollgeist.gemspec
```

## License

Rollgeist is available under the [MIT License](LICENSE.txt).
