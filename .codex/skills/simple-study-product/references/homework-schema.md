# Assignments, answers, and grading

## Supported source

Version 1 reliably imports UTF-8 JSON using .sshomework or .json. Do not silently convert arbitrary PDF/Word documents into scored assignments. They remain source material until an explicit supported extraction/validation workflow succeeds. Small inline images may be represented as data URLs only where the renderer supports them.

Validate complete decoding, schema version, stable/unique IDs, question fields, options, and answer types before committing. Any invalid question rejects the whole import with its location. See [format documentation](../../../../Docs/HomeworkFormat.md) and the project Examples directory.

Required package fields: schemaVersion=1, id, title, questions; optional courseID and lessonSequence.
Each question has id, type, prompt, answer, explanation, points, required, and choice options where applicable.

- singleChoice: exactly one selectedOptionIDs answer.
- multipleChoice: exact set equality, no partial credit.
- fillBlank: acceptedTexts matched character-for-character; do not trim whitespace or ignore case.
- openResponse: referenceText and explanation for self-assessment, no definitive automatic judgment.
- Option IDs are unique within the question; answer IDs must exist.

## Submission

Autosave draft answers. Do not reveal answers before submission. A single submission boundary freezes answers, computes objective results, saves them, and completes the linked task; navigate immediately to grading. AI feedback never blocks this local completion or changes historical scores.

Show the user's answer, result, correct/reference answer, explanation, and points beneath each question. Summaries include total/answered/unanswered counts, objective correct/incorrect counts, score, accuracy, and type breakdown. Exclude open responses from objective accuracy.

## Restart

Confirm before resetting. Clear an unsubmitted draft or create a new blank attempt from a submitted assignment. Preserve all submitted answers and scores. Never reopen or re-remind the original completed task.
