# Alarm management correction

Historical implementation review: September 7, 2026. The observations below came from code, not inspection of a user's physical alarms.

## Causes addressed

The old screen queried app records only, hiding surviving system alarms whose records were lost. Changed device IDs could misclassify local alarms as remote. Read failures appeared stopped, registration IDs were saved too late, and editing/deletion could discard records before cancellation was confirmed.

## Behavior

Merge exact local system IDs with stored records, never guess by title/time. Show unmatched registrations as recovered alarms, using only system-provided time/title information. Offer cancel/stop for current alarms and fold inactive history separately.

Refresh on entry, pull-to-refresh, foreground, and system changes. Management reads must not create alarms, request permissions, or perform blanket cleanup. Read failures retain the last result and show verification/retry.

After cancellation, requery and mark stopped only when the exact ID is absent. Preserve uncertain/failed results. Persist stable IDs before registration and recover using the same ID. Manual cancellation must not recreate an alarm at the next launch.

Editing/deletion retains cancellation failures for retry and stops unsafe replacement. Missing unsynced tasks are not grounds for automatic alarm deletion. Stopping an alarm never completes its task.

## Physical verification procedure

Update the existing app on the ringing device without removing data. Open Settings → Alarms and refresh. Find the exact local/recovered alarm, cancel it, refresh, and relaunch to check it stays absent. Do not cancel unrelated alarms.

Only this app's AlarmKit alarms are managed here. Apple Clock/Shortcut-created Clock alarms remain in Clock. iPad cannot directly cancel an iPhone registration.

## Historical evidence and limits

The earlier review recorded 69 passing simulator tests, including 19 alarm regressions, on iPhone and iPad simulator configurations, plus Debug/Release compilation. Those results are historical, not proof of this build's physical behavior.

No existing user alarms were canceled by this review. Version-27 ringing, cancellation, Focus/Sleep, restart, and cross-device behavior require real-device tests. Reference: [Apple AlarmKit sample](https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit).
