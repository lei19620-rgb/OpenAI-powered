# OpenAI-powered: learning from your own materials

Updated September 16, 2026. The current implementation is the direct-API personal edition described in [implementation notes](Docs/OpenAI-Implementation.md). Earlier backend proposals are superseded, not requirements.

## Copy isolation

Development is restricted to this copy. The original sibling project remains unchanged. This is a same-disk copy, not off-site disaster recovery or an export of device/iCloud learning data.

Xcode target/module names remain SimpleStudy. Display name is Study AI, bundle ID is app.studyai.personal, and the separate CloudKit placeholder is iCloud.app.studyai.personal. Sync defaults off pending provisioning. Personal signing settings, old Git metadata, Xcode user state, and inherited build caches have been removed from this copy. No remote or paid service has been created.

## Product

Help learners understand their selected material without leaving its context. The core loop is source selection → explanation → explicit note append → targeted practice → local grading → optional feedback. Stored results remain available offline.

Keep Today, Study, Words, and Settings. Do not add a competing general-chat library. English interface text is separate from the previously agreed Chinese-first beginner teaching approach.

## Current text-learning scope

- Enter or paste text on Study, or select PDF text and choose Explain.
- Use existing local OCR for scanned materials; do not silently send page images.
- Preview actual text, endpoint, model, token limit, and privacy/cost consequences before every request.
- Explain meaning, concrete sentence components, left-to-right chunks, relevant grammar, simple bilingual examples, and common confusions. Do not use rhetorical self-questioning or teach that English is read backwards.
- Preserve genuine source/page context and validate verbatim quotes against the text snapshot.
- On iPad, show an inspector beside study; on iPhone, a resizable sheet. Avoid overlapping note/assistant layers.
- Append selected explanation sections to the main note without replacing existing writing.
- Generate three structured practice questions, validate through the existing assignment importer, preview, then save by explicit action.
- Keep deterministic local grading. Optional AI feedback does not alter scores or task completion. Open responses receive references, not authoritative exam scores.

AI cannot automatically operate alarms, finish tasks, upload libraries, or replace offline dictionary lookup.

## Architecture and safety

The app calls the Responses API directly with the user's own device-local Keychain key. No shared embedded key, backend, proxy, service account system, server budget reservation, or remote job-resumption infrastructure is included. This is suitable for user-supplied keys, not distributing a developer's secret in a public app.

Input is capped at 6,000 characters. Output limits are user-selected. HTTPS only; reject URL credentials/query/fragment and authenticated redirects. Use strict structured JSON, validate semantics and quotes, and reject refused/incomplete/invalid output.

Treat material as untrusted data. It cannot change teaching instructions or grant permissions. No arbitrary file access, database writes, or model-controlled tools.

Cancellation/timeout may still incur charges. Do not retry paid requests automatically. store=false is not a zero-retention guarantee. Local deletion is not service-side deletion. Token limits are not dollar spending caps.

Save versioned source snapshots, model/service metadata, result, and usage when returned; never store keys in records or logs. Explicit append/import uses existing persistence boundaries. Preserve unsaved results on save failure.

## Future work, not current capability

Possible later stages: course-range guides, vocabulary extraction, source-backed review suggestions, natural-language task drafts, and speech practice. These require independent scope, validation, latency/cost testing, and consent. Speech transcription is not professional phoneme assessment.

Do not add a backend merely because future multi-user deployments may benefit from one. Any different credential/distribution model requires a separate decision.

## Acceptance

Build and unit tests cover implementation contracts, not teaching accuracy or real service availability. Live API validation requires the user's endpoint/model/key at that stage. Review grammar cases (linking verbs, passive, questions/embedded questions, conditions, modifiers, tenses, ambiguity) against trusted answers rather than model self-evaluation.

Physical-device signing, alarms under Focus/Sleep/restart, Pencil, and cross-device iCloud require separate verification. The new identity must never replace the original app's data or register its alarms again.

Official references: [Responses API](https://developers.openai.com/api/reference/cli/resources/responses/methods/create), [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [data controls](https://developers.openai.com/api/docs/guides/your-data).
