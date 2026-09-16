# Workspaces, materials, and editable notes

## Courses and sequence

Courses hold materials, recurrence, accumulation policy, and current pending sequence. Each lesson normally has one workspace with a main note, multiple assets, independent annotations, and optional assignments. Advance only on explicit completion or its defined business event; missed dates consume no lesson.

Inference may use filename keywords (Day/Lesson/Unit and Chinese lesson markers), PDF metadata/first-page/OCR text, natural filename order, existing progress, and completion history. Persist sequence, evidence, and confidence. Renaming does not change established sequence. Allow low-confidence one-step import with later correction rather than per-file questioning.

## PDF and Pencil

Preserve originals read-only. Support zoom, pagination/continuous reading, thumbnails, selection/copy, and search. Run OCR and question extraction asynchronously; failure does not block reading. Store ink per page, with erase/undo/redo; export a new annotated PDF. Large imports, OCR, thumbnails, and export need bounded work, cancellation, progress, and errors.

## Main note

Materials remain primary. A floating control opens the current main note.

- iPad: movable, resizable, full screen, safe within current portrait/landscape window.
- iPhone: compact/half/full-screen presentation constrained by safe areas.
- Autosave content; optionally sync notes, never panel geometry.
- Markdown toolbar, source/preview, and UTF-8 import/export.
- Daily starter: Day N and actual date; Sentence, Words and Expressions, Grammar, Output.
- Confirm Markdown replacement; only replace the body, not relationships or template snapshot.
- Closing the note keeps the study location and preserves edits.

## Templates

Users can create, copy, edit, reorder, import, and export templates. Built-ins are editable starters: sentence study, PDF study, vocabulary, practice review, and blank. Use English document/section headings and optional emoji.

Supported implementation blocks are heading, richText, checklist, quote, table, attachment, divider, handwriting, reviewQuestion. Richer image/status/custom blocks are not promised until implemented and validated.

Resolve course, day, actual date, and material variables at note creation. Future review-date variables require explicit implementation. Save the template version and complete snapshot; never propagate later template changes into existing notes.

## AI companion

Selection passes a text snapshot and actual source page to a separate assistant. iPad uses an inspector, iPhone a sheet. Avoid stacking the note and assistant over the PDF. Show text/service/model before sending. Validate source quotes. Save selected explanation sections by explicit append, never rewrite the full note. Generated assignments pass the existing importer before acceptance.
