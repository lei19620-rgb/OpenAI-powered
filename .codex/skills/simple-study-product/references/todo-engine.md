# Dynamic tasks and action engine

## Model

A task combines basic information, trigger, prerequisites, ordered actions, and a completion rule. Parameters include title/notes/icon/color/category/priority; original scheduled time/time zone/recurrence; optional course/unit/workspace/assignment/vocabulary links; prerequisite IDs with all/any policy; manual or business-event completion (manual default); and action parameters, enabled state, and failure policy.

Supported or planned trigger categories must be checked against implementation: scheduled time, recurrence, prerequisite completion, course progress, manual start, and optional Shortcut entry.

Actions cover target-device alarms, local/repeated notifications, workspace creation/opening, note creation with template variables, current material resolution, study/assignment/vocabulary navigation, review reminders, progress updates, optional Shortcuts, and logs. Do not expose an unimplemented action as working.

## States

Task states: scheduled, waitingDependency, ready, overdue, runningActions, partialFailure, completed, cancelled.
Action states: pending, running, succeeded, failed, skipped.
Use stable idempotency keys, timestamps, error summaries, and retry counters. Retry failed actions only.

Incomplete prerequisites block downstream execution. Once ready, an overdue downstream task remains overdue and actionable; never skip or auto-complete it.

## Recurrence

Default non-accumulating mode retains one outstanding instance across missed occurrences and proceeds after actual completion. Accumulating mode retains a backlog to complete in order. Both preserve original planned times and overdue duration; incomplete instances do not consume course sequence. Recurrence preserves intended clock time rather than drifting with late completion.

## Completion

The app is authoritative. Alarm dismissal, notification opening, or viewing material does not complete work. Assignment completion means a successful submission with local grading. Vocabulary completion means every entry in the linked unit has an initial rating, or every unit in the linked courseware has completed initial learning; raw counts are not sufficient.

Again/Hard/Good/Easy are ratings and review scheduler inputs. Later review never reopens a completed task. Completion actions must respect critical failures: partialFailure blocks downstream progress where required. Noncritical failures remain visible and retryable without undoing a committed business result.

## Edit and delete

Preserve stable task identity, creation time, history, and recurrence lineage. Reevaluate changed actions; do not repeat unchanged successful actions. Cancel old local registrations before replacement, and retain uncertain cancellation records.

Pending tasks support edit/delete; completed records support deletion, not rewriting completion history. Confirm scope. Delete task/logs/associated registrations only, preserving courses, workspaces, notes, materials, and submissions. Remove incoming dependency edges and recompute downstream state, without deleting downstream tasks.

## Alarms

Targets: preferred iPhone (default), current iPad, all authorized devices, or none. Sync intent, then register on each target locally. Show waiting for iPhone until that device confirms registration. States include notRequested, awaitingDevice, scheduled, fired, stopped, failed, permissionDenied.

Registered alarms do not require continuous app background execution. Permissions and system policy still matter; retain the task and offer ordinary notifications on failure. Clear titles/stop controls identify the task. Manage only app AlarmKit alarms, not Apple's Clock alarms. Reconcile exact system IDs with local records, preserve read failures, verify cancellation, and never infer a match from title/time alone.

## Creation UX

Ask when to start → what to do → what the app does on start → what counts as completion → what happens next. Show a compact generated flow, vertical on phones and optionally horizontal on wide iPads, not a complex node editor.

Recipes prefill general behaviors (task, timed reminder, alarm, linked content, sequence, repetition, custom workflow), not personal titles. Categories are optional labels/icons/filters, never fixed business logic. Explain advanced settings on demand, e.g. “Block the next step if this fails.” Validate required links before save and preserve drafts on errors.
