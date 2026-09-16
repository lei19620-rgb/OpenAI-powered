# Vocabulary courseware, version 1

Import UTF-8 `.json`. The entire package must validate before writing. Reimporting the same ID updates courseware while preserving matching entries' review progress where possible.

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | Integer | `1` |
| `type` | String | `vocabulary-courseware` |
| `id` | String | Stable package ID |
| `title` | String | Courseware title |
| `curriculumKey` | Optional string | Indirect course/PDF association |
| `units` | Array | Days, lessons, chapters, or custom groups |
| `items` / `words` / `entries` | Optional array | Ungrouped entries; import offers one unit or fixed-size grouping |

Each unit has `sequence` (starting at 1), `title` (original grouping name), and `items`. Optional: stable `key`, `unitType`, `sourceLabel`, and `expectedCount`. Counts are for checking, not completion.

Entries should provide `key`, `term`, and `meaning`. Optional information includes US/UK phonetics, part of speech, examples, notes, and tags. See [the example](../Examples/vocabulary-courseware-example.json).

Aliases: top-level `groups` for `units`; top-level `items`, `words`, or `entries` for ungrouped lists; unit `words` or `entries` for `items`; entry `word` or `name` for `term`. Storage uses canonical fields.

A unit completes automatically after every entry is presented and rated at least once: Again, Hard, Good, or Easy. Courseware completes when all units complete initial learning. Neither declared counts nor changed word counts alone imply completion.

Ratings feed spaced repetition; weaker words return sooner. Reviews never reopen completed units or tasks. Linked tasks complete automatically when their exact unit/courseware condition is met.
