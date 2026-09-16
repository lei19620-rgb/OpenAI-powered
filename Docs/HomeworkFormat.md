# Assignment format, version 1

Use UTF-8 JSON with extension `.sshomework` or `.json`. Imports are atomic: decode and validate everything before writing. Errors identify the affected question and reject the entire file. Limits: 5 MB and 1,000 questions.

Examples: [Day 01](../Examples/day-01.sshomework) and [four question types](../Examples/homework-example.sshomework).

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | Integer | Must be `1` |
| `id` | String | Stable package ID |
| `title` | String | Assignment title |
| `courseID` | Optional string | External course ID |
| `lessonSequence` | Optional integer | Related lesson sequence |
| `questions` | Array | At least one question |

Every question requires `id`, `type`, `prompt`, `answer`, `explanation`, `points`, and `required`. Option IDs must be unique within a question.

- `singleChoice`: at least two `options`; exactly one `answer.selectedOptionIDs` value.
- `multipleChoice`: the selected set must exactly match the correct set to earn points.
- `fillBlank`: `answer.acceptedTexts` contains accepted strings. Matching is case-sensitive and whitespace-sensitive.
- `openResponse`: `answer.referenceText` supports self-assessment. Open responses are excluded from objective accuracy and are not automatically judged right or wrong.

Submission immediately produces per-question results and a summary. Starting over creates a blank attempt, preserves submitted history, and does not reactivate the completed task.
