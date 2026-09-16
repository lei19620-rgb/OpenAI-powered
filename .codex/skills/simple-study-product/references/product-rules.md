# Product scope and information architecture

Study AI connects reminders, linked materials, notes, practice, and progress while allowing users to rearrange the workflow. Do not hard-code a personal wake-up → notes → vocabulary → homework sequence.

Minimum deployment target is iOS/iPadOS 26.0; the intended physical-device environment also includes version 27. Use SwiftData, CloudKit, AlarmKit, PDFKit, Vision, and PencilKit within supported capabilities. iPad must support portrait and landscape without clipping controls; keep materials primary.

## Top-level navigation

1. Today: tasks, overdue state, dependencies, actions, and continuation.
2. Study: courses, unit progress, workspaces, main notes, materials, ink, and assignments.
3. Words: vocabulary units and spaced repetition; offline dictionary sources are independent of courseware.
4. Settings: actual storage mode, permissions, defaults, imports, examples, privacy, and AI service configuration.

Assignments remain inside Study. Shared import/template entry points must use the same data and implementation.

## Required workflows

- Configure task triggers, prerequisites, reminders, and actions; overdue tasks remain actionable.
- Import materials, persist inferred lesson sequence with evidence/confidence, and allow corrections.
- Open linked workspaces; read/search/copy/OCR PDFs, annotate separately, and use movable notes.
- Create notes from editable templates. Support Markdown exchange without replacing old snapshots.
- Import validated assignment JSON, answer four question types, and immediately review local grading.
- Import generic vocabulary groups, rate each word, automatically complete corresponding units/tasks, and schedule later review.
- Keep dictionary resources local; optionally sync learning records and progress through iCloud.
- Register alarms on the selected physical device and display their actual state.
- Explain selected text, explicitly append chosen AI content to notes, preview/save generated practice, and request optional post-submission feedback.

## Interaction

Use concise English product language, not technical field names. Explain only what is not obvious. Empty states show a real next step, not fake content. Advanced settings expand on demand.

Task creation asks: when to start, what to do, what the app should do on start, what counts as completion, and what happens next. Today explains that downstream tasks wait for completion in the app. Pending tasks support edit/delete; completed history supports delete with clear scope.

Expose waiting, running, partial failure, retry, and completion. Preserve drafts on failure. Confirm destructive changes. Settings checks authorization without requesting it.

## Boundaries

Do not require Apple Notes or Shortcuts for the main flow. Do not claim AlarmKit alarms appear in Apple's Clock list or guarantee ringing in every mode without physical-device evidence. Do not equate word counts with completed units. Do not use online AI as a hidden fallback for offline lookup.

AI outputs are drafts and may be wrong. Model instructions cannot authorize system actions. No automatic alarms, task completion, full-library upload, background paid retries, or authoritative exam scores. No backend is required for this BYOK edition. Real API and physical-device tests remain separate acceptance stages.
