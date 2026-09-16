# Interface, quality, and delivery

## Interaction

Use stable headings/navigation/actions, adaptive layout, safe areas, Dynamic Type, and accessible hit targets. Do not optimize for one fixed screenshot. Keyboard dismissal through background taps, scrolling, submit, and back should follow product rules; navigation must not accidentally become keyboard-driven scrolling content.

Make visible cards/rows/buttons fully actionable. Images, camera, scanning, OCR, and search need cancellation, permission denial, no-result, low-quality, and failure states. Confirm destructive scope. Explain failures and next steps rather than exposing only raw exceptions.

## Reliability and performance

Keep decoding, OCR, files, models, and large queries asynchronous and bounded. Cache/deduplicate repeated inputs. Do not repeatedly read originals in view bodies. Save/import/state transitions have explicit consistency boundaries. Support old formats, missing fields, defaults, and migration failure.

Budget older devices and large data using scoped queries, batching, projections, and input limits. Automatic refresh retains old data; user-initiated save/query may block locally.

## Logs

Record action, outcome, actual error reason, and timing. Normal lifecycle events are informational, not warnings. Avoid personal/business details, source texts, tokens, full paths, and unnecessary financial content. Prefer counts and internal types.

Coalesce high-frequency informational logs; persist failures promptly and flush appropriately without blocking UI. Show included data before feedback attachments. Handoff to a mail client does not prove delivery.

## Verification

- Static: formatting/type checks, builds, resource/privacy manifests, and diff checks where a repository exists.
- Interaction: first use, empty/existing data, save/edit/cancel/exit/delete/reset, repeated taps, keyboard, filters, refresh, loading cleanup.
- Data: migrations, missing fields/files, import/export, duplicate headers, bounds, cross-day/future dates, partial failure.
- Concurrency: rapid navigation/refresh, stale responses, background save, simultaneous import/cleanup/training, cancellation/reentry.
- Devices: target iPhone; also iPad/landscape and denied-permission paths where applicable.
- Delivery: list changes, commands/results, physical installation status, signing/environment limits, and remaining work.

## Release

Build Debug and Release. Release excludes hidden test entry points, credentials, preview fixtures, debug menus, and development-only privileges. Gate tools with compile conditions; inspect built products, not only source.

Validate icon opacity, permission/privacy consistency, version and bundle identity. Build success does not imply Archive/Validate/TestFlight/upload success; report external steps separately.

## Version control

Follow this repository's branch policy, not another project's conventions. Stage only this task's files and preserve unrelated user changes. Make a coherent commit when authorized and appropriate. In anonymized copies, never recreate personal history or reuse personal global Git identity.

Do not commit personal data, private databases, photos, build caches, signing artifacts, feedback bundles, or logs. Check large generated artifacts and ignore rules. Never destroy user work to roll back; use traceable reversal or obtain approval.
