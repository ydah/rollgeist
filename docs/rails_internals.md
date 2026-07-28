# Active Record transaction internals

This document fixes the internal API assumptions used by
`rollgeist` 0.1. Re-run the probe with:

```sh
bundle exec appraisal rails_7_1 ruby script/rails_internals_probe.rb
bundle exec appraisal rails_7_2 ruby script/rails_internals_probe.rb
bundle exec appraisal rails_8_0 ruby script/rails_internals_probe.rb
```

The results below were captured on Ruby 4.0.0 with Active Record 7.1.6,
7.2.3, and 8.0.5. The behavioral spec suite repeats the assumptions on every
supported Appraisal.

## Rollback callbacks

| Scenario | Rails 7.1 | Rails 7.2 | Rails 8.0 |
|---|---|---|---|
| Explicit `ActiveRecord::Rollback` | `rolledback!` called | same | same |
| Exception escaping the transaction | `rolledback!` called | same | same |
| Outer transaction rollback arguments | `force_restore_state: true`, `should_run_callbacks: true` | same | same |
| `requires_new` savepoint rollback arguments | `force_restore_state: false`, `should_run_callbacks: true` | same | same |
| Joined nested `ActiveRecord::Rollback` | no rollback; outer transaction commits | same | same |
| `after_rollback` ordering | runs inside `rolledback!` before it returns | same | same |

The guard therefore captures dirty metadata before `super` and attaches the
mark only after `super` returns. Application `after_rollback` callbacks cannot
observe the mark.

## State restored by `rolledback!`

| Write | Before `super` | After `super` | Attribute values |
|---|---|---|---|
| Create | `new_record? == false`, assigned id | `new_record? == true`, id cleared | submitted values remain in memory |
| Update | persisted, not frozen | persisted, not frozen | updated values remain in memory |
| Destroy | destroyed and frozen | not destroyed and not frozen | values remain in memory |

For update and create, `saved_changes` still contains the attributes written
when `rolledback!` starts. `changes_to_save` is already empty. The guard uses
the former, captured before Rails restores its transaction state.

## Transaction-record registration

| Operation | Added as a transaction record? | v0.1 marking behavior |
|---|---|---|
| Successful create/save | yes | marked on rollback |
| Successful update/save | yes | marked on rollback |
| Destroy | yes | marked on rollback; a later successful destroy also clears an existing mark |
| `update_columns` | no | not detected |
| `touch` | yes | deliberately not marked; direct/timestamp-only writes are outside v0.1 scope |
| Raw SQL | no model transaction record | not detected |

`touch` registration is an important implementation detail: relying only on
the presence of a `rolledback!` callback would broaden the documented scope.
The guard records successful `create_or_update` calls separately so a
touch-only rollback remains unmarked.

## Commit behavior

A record rolled back by a `requires_new` savepoint is not later passed to
`committed!` merely because the outer transaction commits. Its mark therefore
survives the outer commit. Joined nested transactions behave differently:
swallowing `ActiveRecord::Rollback` does not roll back the joined work, and the
record receives `committed!` from the outer transaction.

Successful reload, save, or destroy clears a mark. A later `committed!` is an
additional cleanup point. If that save or destroy is itself rolled back,
`rolledback!` creates a fresh mark after Rails restores the record.

## Compatibility policy

`rolledback!`, `committed!`, and transaction-record registration are internal
APIs. The supported Rails matrix is mandatory CI; Rails main runs as an
allowed-failure compatibility signal so signature or callback-order changes
are visible before the next release.
