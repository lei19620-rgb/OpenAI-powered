# Workflow and interface audit

Updated September 16, 2026. Existing product semantics remain intact; no new top-level business module.

## Preserved workflow safeguards

Dependencies gate start/retry/business completion; cyclic dependencies are rejected. Recurring tasks retain planned clock time and require readiness. Actions run serially, recover interruptions, and retry failures without replaying unchanged successes. Critical failures block downstream work; secondary failures remain visible without undoing committed completion.

App notifications remain useful for overdue work, use independent IDs, and navigate to the correct task. Background refresh does not hijack navigation. Assignment drafts preserve input on save failure, submitted attempts cannot be overwritten, and restart preserves history/task state.

Vocabulary separates new learning from due review and recalculates valid membership on reimport. PDF batches validate before saving, reuse lesson workspaces, and avoid identical duplicates. Completing a later lesson does not skip earlier pending ones.

Notes use editing buffers, delayed saves, and close-time persistence. OCR cancellation cannot write stale results. Ink handles duplicate synced page records and retains failed-save content for retry/export. Storage failure pauses editing instead of using misleading temporary persistence.

PDF limits: 50 MB and 1,000 pages each; 200 MB per batch. Invalid/encrypted files reject the batch.

## Visual changes

Apple-design and emil-design-eng guidance informed native controls, adaptive layouts, restrained emphasis, and reduced small-print clutter.

| Before | After | Why |
| --- | --- | --- |
| Dense explanatory text on routine actions | Short English labels, detail for permissions/errors only | Improve scanning without hiding consequences |
| Study tools lacked a clear AI entry | One Study assistant card plus contextual PDF selection action | Make the approved learning loop discoverable |
| Competing floating layers | iPad inspector; compact-device sheet; note closes safely first | Keep source material readable |
| Generic card hierarchy | Consistent spacing/radii and restrained adaptive jade accent | Make primary actions distinct without heavy decoration |
| Chinese interface and mixed developer material | English UI, permissions, templates, docs, project skills | Establish one project language |
| Old privacy/signing identity | Independent identifiers, local-default storage, no personal hosted policy | Keep the copy separate and remove personal configuration |

Imported content, bilingual dictionary data, and Chinese-compatibility tests intentionally retain their language. AI teaching language remains independent.

## Verification scope

The English conversion passed 82 simulator unit/regression tests with zero failures on September 16, 2026. They cover core product, workflow, alarms, and AI contracts. Final Release and visual checks are tracked separately during delivery.

Preview fixtures use an isolated in-memory store and Debug-simulator-only launch flags; they are not real API output. The screenshots in `UI-Review` were refreshed from the English simulator build; the iPad capture is portrait because the available simulator display mode could not be switched to a landscape geometry during this pass.

Still required: live API integration with user configuration; physical version-27 alarms, permissions/notification interaction, Pencil, signing, and iCloud multi-device behavior. Simulator success does not establish those guarantees.
