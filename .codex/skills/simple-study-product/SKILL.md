---
name: simple-study-product
description: "Product and implementation rules for Study AI. Use when developing, reviewing, or maintaining this project's dynamic tasks, study workspaces, templates, PDF/Pencil, assignments, vocabulary, alarms, direct AI assistance, or iCloud sync. Not for unrelated iOS projects."
---

# Study AI product skill

Build a configurable iPhone/iPad study workflow, not a fixed daily checklist. English learning is the first use case, but task names and actions must also serve reading, mathematics, programming, and other courses.

## Workflow

1. Read the relevant references before changing code.
2. Also follow the project-local common-development skill; these business rules take precedence.
3. Establish ownership, states, failure boundaries, and acceptance criteria before UI work.
4. Actions must be configurable, observable, idempotent, and retryable. Successful actions must not repeat after partial failure.
5. Previously approved decisions remain settled unless a new request changes persistence, sync, or irreversible behavior.
6. Build and test core behavior and empty/error states. Distinguish simulator evidence from physical-device verification.

## References

- Product scope and acceptance: [product-rules](references/product-rules.md).
- Tasks, actions, overdue handling, alarms: [todo-engine](references/todo-engine.md).
- Courses, PDF, Pencil, templates, notes: [study-workspace](references/study-workspace.md).
- Assignment schema, answers, grading, reset: [homework-schema](references/homework-schema.md).
- Storage, sync, device state, consistency: [data-and-sync](references/data-and-sync.md).

## Invariants

- The app is the source of truth for task completion. Dismissing an alarm never completes a task.
- Preserve planned times and overdue status. Accumulation is a plan option; incomplete prerequisites block downstream tasks and lesson advancement.
- Default to one workspace and main note per lesson. Template edits never change old note snapshots.
- Preserve original PDFs; store ink independently and export a new annotated file.
- Grade objective answers locally on submission. Open responses show references for self-assessment, not authoritative scores.
- A new assignment attempt preserves submissions and never reactivates the original task.
- Core business data may sync; alarm registration, note geometry, dictionaries, and API keys stay device-local.
- This independent edition defaults to local storage. iCloud preferences apply next launch, and disabling sync does not erase cloud copies.
- Permissions are requested only through explicit user action. Settings shows actual status and available fallbacks.
- Vocabulary uses generic units, not mandatory Day labels. Every item must receive an initial rating; review does not reopen completed units or tasks.
- Dictionary lookup stays offline, supports words/phrases, and does not invent missing translations.
- AI is an explicit, separately consented network action. Use direct Responses API with the user's own key, no required backend. Never embed a shared key or upload entire libraries.
- Project UI, documentation, comments, and built-in template labels are English. Preserve imported languages, bilingual dictionary data, and language-compatibility tests.
- Preserve Chinese-first beginner teaching until explicitly changed; teaching language and app language are separate.
