# General development conventions

## Scope and ownership

Read current product decisions and implementation before changing code. Product-specific rules and the latest explicit user decision override generic preferences and historical experiments. Trace real entry points, state owners, persistence, and downstream consumers, not just visible views.

For each state establish its producer, authorized writers, effective time, cleanup, and failure retention. Separate durable records, page state, drafts, caches, and temporary sessions. Navigation, formats, persistence, permissions, and external services are high-impact changes requiring clear authorization. Favor direct, recoverable workflows; progressively disclose advanced controls.

## Names and labels

Use clear English domain names and explicit units in code. Store money as minor-unit integers or equivalent exact types. Maintain one enum and display mapping per state; labels, filters, and metrics must agree. Show product language rather than raw enum names, debug text, or placeholders. Search for existing terminology before adding alternatives. Centralize layout tokens.

## Feedback and interaction

Keep page titles, primary actions, and navigation stable across scrolling, keyboards, loading, and empty states. Avoid repeating choices made in a parent screen. Make entire visible rows/cards/buttons tappable, not just small arrows.

Provide clear completion/cancel/back/keyboard-dismissal paths. Preserve drafts on failure. Distinguish empty data, denied permission, unsupported format, and no results with actionable next steps. Confirm destructive scope, recoverability, and unaffected content in context.

## Refresh and search

Load on first entry; update affected data after edits/imports rather than rebuilding navigation. Mutable lists need a real refresh path that always restores interaction. Debounce, index, paginate, or submit expensive searches. Reset to a valid first page when filters change, while retaining a clear-filters action.

Handle duplicate taps, concurrent refresh, and late stale responses; only current results may update UI. Refresh must not erase drafts, selected images, or temporary filters. Preserve scroll/filter context after row edits. Background updates retain old data; explicit user queries/saves may use blocking feedback.

## Time

Persist Date, UTC/ISO-8601, or native database time, never only formatted display text. Use device Locale, Calendar, and time zone for presentation. Distinguish created, updated, event, scheduled, and completed times. Day queries use local-calendar half-open intervals from startOfDay to the next startOfDay, not string prefixes or fixed 24-hour assumptions.

Missing dates follow explicit product fallback rules and must not appear user-entered. Preserve historical business snapshots; mark unrecoverable old data as estimated/missing.

Date-range selection should not trigger large queries until confirmed. Validate reversed, missing, future, or excessive ranges without disabling the page or losing input. Allow cross-year ranges. Choose controls suited to complexity. Include a selected end date by querying to the next day at midnight, not 23:59:59.

## Privacy and input

Store only necessary fields; clean temporary files on success/cancel/failure. Validate versions, types, relationships, and duplicates before atomic import. Version export formats and explain scope, time, merge/overwrite effects, and recovery.

Request permissions only when the relevant feature is explicitly used, not all at first launch. External uploads require authorization plus privacy, failure, and safety design. Local storage, sandbox protection, and independent encryption are different promises; documentation and code must agree.
