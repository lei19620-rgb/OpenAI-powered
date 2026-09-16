---
name: common-development
description: "Reusable engineering standards for software development, review, and maintenance: requirements, state boundaries, interaction, async work, consistency, performance, privacy, validation, and delivery. Keep business rules in the project product skill."
---

# Common development standards

Read the repository's product skill, AGENTS.md if present, branch rules, and implementation first. Use this baseline to supplement engineering quality, not duplicate business truth.

## Workflow

1. Inspect changes, branch/history when available, entry points, state owners, and persistence. Separate existing user work from your changes.
2. Identify inputs, long-lived/transient state, success, cancellation/failure, and acceptance criteria.
3. Distinguish cancelable preparation, protected commit, background refresh, and explicit refresh.
4. Prefer scoped changes that preserve navigation, semantics, and input. Do not expand permissions, collection, or external effects without authorization.
5. Validate according to risk: interactions, migration, cancellation, repeated taps, lifecycle, and Release.
6. Stage only intended files and follow repository delivery rules. Never restore removed personal history or commit with an unapproved personal identity in an anonymized copy.

## Invariants

- Consistent product vocabulary, enums, labels, filters, and statistics.
- Loading, empty, error, and completion feedback, including cancellation and superseded requests.
- Clear save/delete/import/export/confirmation boundaries; post-processing failure must not falsify committed success.
- Bounded background work for files, images, OCR, models, lists, and database scans; cross executors using immutable values or stable IDs.
- Confirm destructive scope; prevent duplicate commits and silent navigation during commit.
- Native time values, lossless money types, device calendar/time zone.
- Request permissions only in context; minimize logs, feedback, and exports.
- No unauthorized servers, accounts, cloud sync, or uploads.
- Fail closed on storage/migration/identity failure: preserve data and stop unsafe writes instead of pretending temporary data is durable.

## Required references by task

- Requirements, labels, lists, time, permissions: [conventions](references/conventions.md).
- Async work, commits, database concurrency, caches, external input: [async/data integrity](references/async-and-data-integrity.md).
- Startup, OCR, aggregation, recovery, performance: [performance/data](references/performance-and-data.md).
- UI, logs, tests, Release, delivery: [quality/delivery](references/quality-and-delivery.md).
