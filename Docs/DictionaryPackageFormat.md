# Offline dictionary format

Lookup uses device-local data only, supports words and short phrases rather than sentences, and never falls back to network translation. Source packages and indexes do not enter SwiftData or iCloud. User JSON entries take priority over the bundled read-only SQLite index. English-to-Chinese and Chinese-to-English are supported.

## Bundled index

`SimpleStudy/Resources/SimpleStudyDictionary.sqlite` is generated before runtime:

```bash
python3 Tools/build_dictionary_index.py \
  --ecdict /path/to/stardict.db \
  --ipa-us /path/to/en_US.txt \
  --ipa-uk /path/to/en_UK.txt \
  --oewn-jsonl /path/to/oewn.jsonl \
  --output SimpleStudy/Resources/SimpleStudyDictionary.sqlite
```

Sources: ECDICT for definitions, parts of speech, inflections, frequency and tags; IPA-Dict for US/UK IPA; Open English WordNet for definitions, examples, synonyms, and semantic relations.

Tables: `metadata`, `sources`, `entries`, `translation_index`, and `phrase_index`. Entries include normalized/original headwords, phrase flags, IPA, Chinese/English definitions, examples, relations, forms, frequency, tags, ranking, and provenance. Phrase indexing finds expressions containing a word.

English lookup uses exact then prefix headword matching; Chinese lookup uses segmented translation exact then prefix matching. Queries exceeding six words or sixteen Chinese characters receive a selection-range hint. Details derive numbered senses and sections from source data.

## User packages

Fields: `schemaVersion` (`1`), `id`, `title`, `language` (defaults to `en`), and `entries`.

Entries contain unique `id`, `headword`, `pronunciation`, `partOfSpeech`, `definition`, `example`, and optional `isPhrase`. Optional: `pronunciationUS`, `pronunciationUK`, `englishDefinition`, `synonyms`, `antonyms`, `forms`, `frequency`, `tags`, and `sourceName`.

Explicit `senses` contain `partOfSpeech`, `translation`, `englishDefinition`, and `note`; `phrases` contain `expression`, `translation`, `partOfSpeech`, and `kind` (`phrase` or `idiom`). Otherwise definitions are split automatically. Different entry IDs may share a headword. [Example](../Examples/dictionary-example.json). Bilingual definitions intentionally remain learning data.

## Eudic originals

Local `.eudic` files may exist under `SimpleStudy/Resources/LocalDictionaries/`. They must not be committed or redistributed without authorization. Packaging them does not make them searchable: the current layer requires a supported index or JSON export, not encrypted proprietary binaries.

The local set includes `Bu_Ze_Shou_Duan_Bei_Dan_Ci`, `en_21shijishuangxiangcidian`, `ciyuan_en`, `ncce-ec`, `cigen_en_classic`, `Concise_English_Synonym_and_Antonym_Dictionary`, `cigen_en_new`, and `IELTS_Basic_Vocabulary` (all `.eudic`). A lawful parser or permitted export is required.

## Pronunciation and licensing

Available US/UK IPA is displayed. Playback uses installed device `en-US` or `en-GB` voices without downloading audio or making lookup requests. Missing IPA is not fabricated. Reverse lookup plays the English result.

Database metadata records source names, versions, and links. See [notices](ThirdPartyDictionaryNotices.md). Verify attribution and distribution obligations for the exact shipped versions; public availability does not eliminate licensing requirements.
