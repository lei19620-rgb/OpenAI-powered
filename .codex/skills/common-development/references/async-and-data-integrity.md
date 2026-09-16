# Async work and data integrity

## Operation types

- Automatic refresh: show the last valid state, compute in background, replace atomically.
- Explicit query: local loading, cancellation, cleanup on exit.
- User write: cancelable preparation, then protected commit with duplicate submission/navigation prevention.
- Secondary processing: notifications, caches, summaries after main persistence; compensate failures without misreporting the primary save.

Represent these phases explicitly rather than using one ambiguous loading flag.

## Lifecycle

Every task has an owner, cancellation boundary, and result-validity check. Use generation tokens, snapshots, debouncing, or cancellation so only the latest request writes back. Cancel and clear references on replacement, exit, background, or session close as appropriate. Every end path restores loading and controls.

Detached work needs explicit handles/cancellation handlers and checks between batches. Track one pending rerun if data changes during automatic computation, consuming it on every outcome. Retain previous results on failed refresh.

## Database isolation

Access managed objects only on their owning context/executor. Cross queues with stable IDs or immutable Sendable snapshots, not managed objects/controllers/mutable collections. Use background contexts, predicates, indexes, batch sizes, and projected fields for large queries. Aggregate once per snapshot instead of repeated whole-table view computations.

For background save notifications, extract object IDs/values on the sending queue before switching. Keep reproducible schema/migration chains and old database fixtures rather than trusting current runtime inference.

## Commit and recovery

Read/parse/preview → validate/deduplicate → atomic commit → primary success → compensatable post-processing.

Perform predictable checks before commit. Use transactions, one save, or an explicit compensation strategy. Lock relevant controls and dismiss/back during persistence. Roll back only the failed transaction, not previous durable work. Never label a committed import as failed because a later notification failed.

Define authoritative source and commit order across database/files/preferences/cache; update derived caches after authority commits. On load/migration failure preserve files and enter recovery; never accept writes into a temporary in-memory store while implying persistence.

## Shared state and caches

Serialize the entire load-modify-save-cache transaction with an actor, serial queue, or lock; locking only read/write fragments loses updates. Never overwrite new state from an unlocked stale snapshot. Centralize invalidation across cleanup/import/edit/training. Cache keys include data/filter/model versions; stale tasks must not block future recomputation.

## Untrusted inputs

Bound bytes before decode and bound rows, objects, strings, dates, and numbers during parsing. Reject duplicate headers, missing fields, unknown enums, invalid dates/numbers, NaN/infinity, overflows, and huge arrays with useful errors, never fatalError/forced unwrap.

Bound file count and batch totals. Parse off-main and balance security-scoped access. Authenticate participants before directed exchange; public broadcast data is not secret. Recheck authorization after membership changes. Clean temporary state idempotently on cancel/removal/disconnect/background/end. Receivers independently validate identity, protocol, scope, and limits.
