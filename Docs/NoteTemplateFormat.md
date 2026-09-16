# Note template JSON, version 1

Use UTF-8 JSON with `schemaVersion: 1`. Recommended extension: `.sstemplate.json`; ordinary `.json` also works. See [the complete example](../Examples/note-template-example.sstemplate.json).

| Field | Type | Requirement |
| --- | --- | --- |
| `schemaVersion` | Integer | Must be `1` |
| `name` | String | 1–80 characters |
| `details` | String | Up to 1,000 characters; may be empty |
| `sourceVersion` | Integer | Exported version; import creates a new version-1 template |
| `blocks` | Array | 1–100 blocks |

Each block requires a unique UUID `id`, `kind`, `title` of 1–120 characters, and `placeholder` of up to 1,000 characters (may be empty).

Kinds: `heading`, `richText`, `checklist`, `quote`, `table`, `attachment`, `divider`, `handwriting`, and `reviewQuestion`. The first heading becomes Markdown `#`; later headings become `##`. Quote blocks use bold titles.

Titles and placeholders support `{{course}}`, `{{day}}`, `{{date}}`, and `{{material}}`. Values resolve when a note is created. Later template edits never change existing notes.

Built-ins follow document title → section heading → content, with optional editable emoji. They are starting points, not mandatory layouts.

Maximum file size: 1 MB. Validate the complete file before saving. Invalid fields or duplicate block IDs reject the whole import. Import creates a new template and never replaces an existing one.
