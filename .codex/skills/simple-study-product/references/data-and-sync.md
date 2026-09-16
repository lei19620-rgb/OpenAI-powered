# Data, synchronization, and consistency

## Ownership

SwiftData is the local business source of truth. Optional private CloudKit sync covers tasks/dependencies/action parameters and logs; courses/lesson sequences/workspaces/progress; templates/note snapshots; PDF and assignment attachments/OCR/ink; drafts/submissions/results; vocabulary units/initial ratings/review schedules; and saved AI study records.

Device-local state includes AlarmKit authorization/registration, floating note geometry, preferences, temporary caches, dictionary packages/indexes, and API keys. Keys use WhenUnlockedThisDeviceOnly Keychain storage, never CloudKit, source files, or logs.

## CloudKit

- No separate app account; use the user's private database.
- Default off in this independent edition until the separate container is provisioned. The preference is per-device and applies next launch.
- Never replace ModelContainer during a live session or force-exit as a restart.
- Show the actual active storage mode, not merely the requested preference.
- Disabling sync stops future device synchronization but does not delete existing cloud copies.
- Stable UUIDs and action idempotency keys are mandatory. Large attachments use external storage.
- Save locally first. Never label a local write as confirmed cloud synchronization.
- Product states must distinguish local, pending, confirmed sync, and failure when those states can actually be observed.
- Preserve conflicting note contents with recovery copies instead of silently discarding one side.

## Cross-device actions

Task intent and preferred alarm device may sync; registration happens locally on each authorized target. Report device ID, result, and time. An iPad cannot remotely guarantee an iPhone alarm registration or cancellation. Only local actions may legitimately execute once per device. Shared actions must avoid duplicate workspace/note creation through stable identifiers.

## Deletion

Task deletion removes task records/logs and cleans associated local alarms/notifications. Preserve cancellation failures for retry; do not discard the only record of a potentially live alarm. Remove dependency edges, not downstream tasks or study content. Completed task deletion also requires confirmation and preserves assignment history.

Show affected workspace/note/material/assignment counts before deleting a course. Detach or explain references before deleting attachments. Template deletion leaves note snapshots unchanged. Assignment reset does not delete submitted history.

## Degradation and preferences

No iCloud: full local study with truthful unsynced status. No alarm permission: retain tasks and offer ordinary notifications. OCR failure: retain the PDF and allow retry. Storage or migration failure: preserve files, stop unsafe writes, and expose recovery rather than fake temporary success.

UserDefaults stores appearance, default alarm target, overdue strategy, template, and sync preference. Defaults affect future records only. Read live permission/account status; file access uses explicit system picking rather than persistent library-wide access.
