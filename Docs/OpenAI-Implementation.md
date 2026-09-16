# Study AI direct-API implementation

Updated September 16, 2026. This supersedes earlier server proposals.

## Architecture

App → user-configured OpenAI Responses API. No developer backend, proxy, or app account system. Default base URL: https://api.openai.com/v1. The model is left for real integration setup rather than assuming account availability.

Keys use device-only Keychain storage with WhenUnlockedThisDeviceOnly accessibility. They are excluded from code, logs, and CloudKit. This is a BYOK personal edition, not a way to distribute a shared developer key. The app is not an official OpenAI product.

## Entry points

- Study home: input/paste text and browse saved assistant records.
- PDF: Explain selected text, retaining asset ID, first selected page, and a text snapshot/hash. Existing local OCR handles scans; page images are not sent automatically.
- iPad inspector and iPhone sheet retain the study context.
- Explanations follow Chinese-first beginner teaching with concrete English components and bilingual examples. Project/interface language is English.
- Explicitly append checked sections to the main note; never replace old content. Standalone results can be shared.
- Practice: strict structured output, existing assignment validation, preview, explicit save.
- Grading: local objective results do not wait for AI; optional feedback does not alter scores. Open responses remain self-assessed.

## Request and failure boundaries

Confirm actual text, endpoint, and model before sending. Maximum input is 6,000 characters; UI output choices are 2,000/4,000/8,000 tokens. Only HTTPS endpoints without URL credentials, query, or fragment are accepted. Authenticated redirects are blocked.

Use store=false without claiming zero retention. No background upload, automatic paid retry, automatic dictionary fallback, or task mutation. Repeated taps are locked during generation. Cancellation, timeout, and incomplete responses warn about possible charges.

There is no server budget reservation, cross-device billing lock, or hard dollar cap. Token limits do not replace account budget management.

Refusals, incomplete responses, invalid JSON, fabricated quotes, and invalid answer references never become valid assignments. Saved records remain readable offline. Deleting a record does not cascade to appended notes or saved assignments.

## Identity and privacy

- Bundle: app.studyai.personal; tests: app.studyai.personal.tests.
- CloudKit placeholder: iCloud.app.studyai.personal; default off pending provisioning.
- Configure signing yourself before physical deployment.
- Personal names, emails, signing team, local absolute paths, inherited Git history, user workspace state, and build caches are excluded from this copy.
- The personal hosted privacy-policy reference is removed. In-app privacy and third-party official policy links remain.
- Build/test output stays outside the project.

## Teaching rules and skills

Teaching instructions are versioned in AITeachingRules. They are not ChatGPT Study Mode or a hosted Agent Skill. No tool-execution sandbox is required. Offline dictionary lookup remains separate from explicitly approved AI requests.

## Verification

Tests cover request shape, safe endpoints, missing credentials, input bounds, quotes, refusals, incomplete output, practice validation, export, and persistence. Live requests await user configuration and are not simulated by presenting fixtures as real outputs.

CloudKit provisioning, device alarms/notifications, Pencil, signing, and multi-device sync still need physical verification. See [workflow/UI audit](Workflow-UI-Audit.md).

Sources: [Responses](https://developers.openai.com/api/reference/cli/resources/responses/methods/create), [structured output](https://developers.openai.com/api/docs/guides/structured-outputs), [data controls](https://developers.openai.com/api/docs/guides/your-data).
