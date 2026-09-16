# Performance, threading, and data safety

## Startup and lifecycle

Present an interactive shell or lightweight local state first. Do not serialize migrations, backups, indexing, thumbnail warmup, and aggregation ahead of the first frame. Classify work as first-screen required, deferred, or data-change-only. Check dirty flags/versions/time windows before backup, cleanup, or reindexing.

Create tabs lazily. Hidden pages must not run expensive queries/OCR/models/statistics. Background transitions save only necessary coalesced state; protect sensitive surfaces and clean temporary sessions as specified without duplicate writes.

## Concurrency

Observable UI follows main-actor rules; decoding, files, OCR, features, statistics, and bulk filtering run off-main and return small final results. Each task has ownership, cancellation, and validity checks. Cancel old tasks on input replacement or exit. Use generations/snapshots/versioning and coalesce identical work.

Serialize capture sessions. Do not use Task.detached to bypass isolation casually; retain cancellation handles and pass immutable values or stable IDs.

## Images, OCR, and models

Use originals only when needed. Downsample to target display dimensions before preview/list decoding. Bound imported image dimensions/quality/bytes according to tested recognition needs. Cache thumbnails with cost limits and invalidate on deletion/replacement/import/memory pressure.

Cache OCR/features by content digest. Bound batch concurrency and sample counts. Narrow candidates cheaply before expensive comparison. End work explicitly on cancellation, poor quality, or no results. Separate temporary exchange/export data from durable files and clean on every outcome.

## Lists and aggregation

Produce filter/group/count/sort snapshots in a single pass where possible; avoid repeated full-array operations in view bodies. Cache stable derived keys and invalidate precisely. Use stable IDs and lazy containers. Rows must not read files, perform OCR, create formatters, or launch unbounded work.

Fetch bounded projections/snapshots before background aggregation. Handle zero/single-point charts, long labels, and empty states. Test large datasets, peak memory, fast scrolling, repeated searches, tabs, and lifecycle on older devices.

## Persistence and recovery

Use transactions or atomic replacement across core data and required associated state. Coalesce backups by data changes with bounded retention. Show external backup location and actual write results; sandbox backups do not imply uninstall recovery.

Validate schema, files, IDs, and references before import/restore. Confirm overwrite and create necessary recovery backups. New fields need compatible defaults and migrations. Caches are rebuildable, never business truth.

## Measurement

Measure cold/warm launch, first screen, search, recognition, import, backup, and aggregation with Release-like data. Check main-thread/concurrency warnings, memory/decode peaks, duplicate tasks, and file handles. Recheck the same paths after changes. Optimization must preserve semantics and freshness after edit/delete/import/restore/migration.
