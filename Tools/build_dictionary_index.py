#!/usr/bin/env python3
"""Build the read-only dictionary index shipped with SimpleStudy.

The app deliberately does not parse large dictionary source files at runtime.
This build-time tool converts ECDICT's SQLite release into a smaller,
query-oriented SQLite database and optionally enriches it with IPA-Dict and
Open English WordNet records.

Example:
    python3 Tools/build_dictionary_index.py \
        --ecdict /private/tmp/ecdict-extracted/stardict.db \
        --ipa-us /private/tmp/ipa-en_US.txt \
        --ipa-uk /private/tmp/ipa-en_UK.txt \
        --oewn-jsonl /private/tmp/oewn.jsonl \
        --output SimpleStudy/Resources/SimpleStudyDictionary.sqlite

The resulting database is read-only at runtime. It contains no user data.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import tempfile
import unicodedata
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator


MAX_TEXT_LENGTH = 100_000
SOURCE_ECDICT_ID = "ecdict"
SOURCE_IPA_DICT_ID = "ipa-dict"
SOURCE_OEWN_ID = "oewn"
SOURCE_ECDICT = "ECDICT"
SOURCE_IPA_DICT = "IPA-Dict"
SOURCE_OEWN = "Open English WordNet"


def normalize(value: str) -> str:
    """Keep lookup normalization identical to DictionaryTextNormalizer.swift."""

    folded = unicodedata.normalize("NFKD", value)
    folded = "".join(character for character in folded if not unicodedata.combining(character))
    folded = (
        folded.replace("’", "'")
        .replace("‘", "'")
        .replace("＇", "'")
        .replace("–", "-")
        .replace("—", "-")
        .casefold()
    )
    punctuation = ".,;:!?()[]{}\"“”…"
    tokens = [token.strip(punctuation) for token in folded.split()]
    return " ".join(token for token in tokens if token)


def text(value: object | None, limit: int = MAX_TEXT_LENGTH) -> str:
    if value is None:
        return ""
    value = str(value).replace("\x00", "").strip()
    return value[:limit]


def unique_values(values: Iterable[str], limit: int = 12) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        value = text(value)
        if not value or value.casefold() in seen:
            continue
        seen.add(value.casefold())
        result.append(value)
        if len(result) >= limit:
            break
    return result


def join_values(values: Iterable[str], separator: str = "\n\n", limit: int = 3) -> str:
    return separator.join(unique_values(values, limit=limit))


def contains_cjk(value: str) -> bool:
    return any(
        "\u3400" <= character <= "\u4dbf"
        or "\u4e00" <= character <= "\u9fff"
        or "\uf900" <= character <= "\ufaff"
        for character in value
    )


def translation_terms(value: object | None) -> list[str]:
    """Extract short Chinese meaning terms for Chinese -> English lookup."""

    raw = text(value, limit=20_000)
    if not raw:
        return []

    terms: list[str] = []
    seen: set[str] = set()
    for part in re.split(r"[,，;；、/|\n]+", raw):
        # ECDICT prefixes individual meanings with POS or bracketed domain labels.
        part = re.sub(r"^\s*[A-Za-z]{1,8}\.\s*", "", part)
        part = re.sub(r"^\s*\[[^\]]{1,24}\]\s*", "", part)
        part = part.strip(" .,:;!?()[]{}\"“”…，；、（）")
        normalized = normalize(part)
        if not normalized or not contains_cjk(normalized) or len(normalized) > 80:
            continue
        if normalized in seen:
            continue
        seen.add(normalized)
        terms.append(normalized)
    return terms


def read_ipa_file(path: Path) -> dict[str, str]:
    """Read IPA-Dict's tab-separated [word][TAB][IPA] source."""

    readings: defaultdict[str, list[str]] = defaultdict(list)
    with path.open("r", encoding="utf-8-sig", errors="replace") as handle:
        for line in handle:
            raw = line.rstrip("\r\n")
            if "\t" not in raw:
                continue
            headword, pronunciation = raw.split("\t", 1)
            key = normalize(headword)
            pronunciation = text(pronunciation, limit=400)
            if not key or not pronunciation or pronunciation in readings[key]:
                continue
            readings[key].append(pronunciation)
    return {key: ", ".join(values) for key, values in readings.items()}


def read_oewn_jsonl(path: Path) -> dict[str, dict[str, list[str] | str]]:
    """Read normalized records emitted by export_oewn_records.rb.

    The intermediate JSONL format keeps the Ruby/YAML parser out of the iOS
    build and lets this script remain usable with future WordNet releases.
    """

    result: dict[str, dict[str, list[str] | str]] = {}
    with path.open("r", encoding="utf-8-sig", errors="replace") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"Invalid Open English WordNet JSONL at line {line_number}: {error}") from error

            headword = text(record.get("headword"), limit=500)
            key = normalize(headword)
            if not key:
                continue

            current = result.setdefault(
                key,
                {
                    "part_of_speech": "",
                    "definitions": [],
                    "examples": [],
                    "synonyms": [],
                    "antonyms": [],
                },
            )
            if not current["part_of_speech"]:
                current["part_of_speech"] = text(record.get("partOfSpeech"), limit=32)
            for field, target in (
                ("definitions", "definitions"),
                ("examples", "examples"),
                ("synonyms", "synonyms"),
                ("antonyms", "antonyms"),
            ):
                values = record.get(field, [])
                if isinstance(values, str):
                    values = [values]
                if isinstance(values, list):
                    current[target].extend(text(value, limit=MAX_TEXT_LENGTH) for value in values)

    for record in result.values():
        for key in ("definitions", "examples", "synonyms", "antonyms"):
            record[key] = unique_values(record[key], limit=20)
    return result


def parse_forms(exchange: object | None) -> str:
    """Turn ECDICT's compact exchange field into a learner-readable list."""

    values: list[str] = []
    for item in text(exchange, limit=4_000).split("/"):
        if ":" not in item:
            continue
        _, value = item.split(":", 1)
        if value:
            values.append(value)
    return ", ".join(unique_values(values, limit=20))


POS_LABELS = {
    "n": "n.",
    "v": "v.",
    "vt": "v.",
    "vi": "v.",
    "a": "adj.",
    "j": "adj.",
    "ad": "adv.",
    "r": "adv.",
    "prep": "prep.",
    "conj": "conj.",
    "pron": "pron.",
    "num": "num.",
    "art": "art.",
    "aux": "aux.",
}


def display_part_of_speech(value: object | None) -> str:
    """Convert ECDICT's weighted POS field (for example n:100/v:96)."""

    raw = text(value, limit=64)
    if not raw or ":" not in raw:
        return raw

    labels: list[str] = []
    for token in re.split(r"[/,;]+", raw):
        code = token.split(":", 1)[0].strip().casefold()
        if not code:
            continue
        label = POS_LABELS.get(code, f"{code}.")
        if label not in labels:
            labels.append(label)
    return " / ".join(labels) or raw


PHRASE_INDEX_STOPWORDS = {
    "a", "an", "and", "as", "at", "be", "by", "for", "from", "in", "into",
    "is", "it", "of", "on", "or", "the", "to", "with",
}


def phrase_index_tokens(normalized: str) -> list[str]:
    """Index meaningful phrase tokens without making stopword searches noisy."""

    return unique_values(
        token
        for token in normalized.split()
        if len(token) >= 2 and token not in PHRASE_INDEX_STOPWORDS
    )


def safe_int(value: object | None) -> int | None:
    try:
        if value is None or str(value).strip() == "":
            return None
        return int(value)
    except (TypeError, ValueError, OverflowError):
        return None


def priority(*, collins: object | None, oxford: object | None, frequency: int | None, has_definition: bool) -> int:
    score = 0
    if safe_int(collins) and safe_int(collins) > 0:
        score += 2_000_000
    if safe_int(oxford) and safe_int(oxford) > 0:
        score += 1_000_000
    if frequency is not None and frequency > 0:
        score += max(0, 500_000 - frequency)
    if has_definition:
        score += 10_000
    return score


def create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        PRAGMA page_size = 4096;
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        PRAGMA temp_store = MEMORY;
        PRAGMA user_version = 3;

        CREATE TABLE metadata (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );

        CREATE TABLE sources (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            license TEXT NOT NULL,
            url TEXT NOT NULL
        );

        CREATE TABLE entries (
            id INTEGER PRIMARY KEY NOT NULL,
            normalized TEXT NOT NULL,
            headword TEXT NOT NULL,
            is_phrase INTEGER NOT NULL,
            pronunciation_us TEXT NOT NULL DEFAULT '',
            pronunciation_uk TEXT NOT NULL DEFAULT '',
            part_of_speech TEXT NOT NULL DEFAULT '',
            translation TEXT NOT NULL DEFAULT '',
            english_definition TEXT NOT NULL DEFAULT '',
            example TEXT NOT NULL DEFAULT '',
            synonyms TEXT NOT NULL DEFAULT '',
            antonyms TEXT NOT NULL DEFAULT '',
            forms TEXT NOT NULL DEFAULT '',
            frequency INTEGER,
            tags TEXT NOT NULL DEFAULT '',
            priority INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL
        );

        CREATE TABLE translation_index (
            normalized TEXT NOT NULL,
            entry_id INTEGER NOT NULL,
            PRIMARY KEY (normalized, entry_id),
            FOREIGN KEY (entry_id) REFERENCES entries(id)
        ) WITHOUT ROWID;

        CREATE TABLE phrase_index (
            token TEXT NOT NULL,
            entry_id INTEGER NOT NULL,
            PRIMARY KEY (token, entry_id),
            FOREIGN KEY (entry_id) REFERENCES entries(id)
        ) WITHOUT ROWID;
        """
    )
    connection.executemany(
        "INSERT INTO sources (id, name, version, license, url) VALUES (?, ?, ?, ?, ?)",
        [
            (SOURCE_ECDICT_ID, SOURCE_ECDICT, "1.0.28", "MIT (verify repository and dataset provenance)", "https://github.com/skywind3000/ECDICT"),
            (SOURCE_IPA_DICT_ID, "IPA-Dict en_US / en_UK", "current source", "MIT / GPL (UK source includes GPL data)", "https://github.com/open-dict-data/ipa-dict"),
            (SOURCE_OEWN_ID, SOURCE_OEWN, "current source", "CC BY 4.0", "https://github.com/globalwordnet/english-wordnet"),
        ],
    )


def build_index(
    *,
    ecdict_path: Path,
    ipa_us_path: Path | None,
    ipa_uk_path: Path | None,
    oewn_path: Path | None,
    output_path: Path,
) -> tuple[int, int]:
    ipa_us = read_ipa_file(ipa_us_path) if ipa_us_path else {}
    ipa_uk = read_ipa_file(ipa_uk_path) if ipa_uk_path else {}
    oewn = read_oewn_jsonl(oewn_path) if oewn_path else {}

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    source_connection: sqlite3.Connection | None = None
    target_connection: sqlite3.Connection | None = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix=f"{output_path.stem}-",
            suffix=".sqlite.tmp",
            dir=output_path.parent,
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)

        target_connection = sqlite3.connect(temporary_path)
        create_schema(target_connection)

        source_connection = sqlite3.connect(f"file:{ecdict_path}?mode=ro", uri=True)
        source_connection.row_factory = sqlite3.Row
        source_cursor = source_connection.execute(
            """
            SELECT word, phonetic, definition, translation, pos,
                   collins, oxford, tag, frq, exchange
            FROM stardict
            ORDER BY id
            """
        )

        insert_sql = """
            INSERT INTO entries (
                normalized, headword, is_phrase, pronunciation_us,
                pronunciation_uk, part_of_speech, translation,
                english_definition, example, synonyms, antonyms, forms,
                frequency, tags, priority, source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        translation_insert_sql = """
            INSERT OR IGNORE INTO translation_index (normalized, entry_id)
            VALUES (?, ?)
        """
        phrase_insert_sql = """
            INSERT OR IGNORE INTO phrase_index (token, entry_id)
            VALUES (?, ?)
        """
        batch: list[tuple[object, ...]] = []
        translation_batch: list[tuple[str, int]] = []
        phrase_batch: list[tuple[str, int]] = []
        seen_oewn: set[str] = set()
        entry_count = 0

        for row in source_cursor:
            headword = text(row["word"], limit=500)
            normalized = normalize(headword)
            if not normalized:
                continue

            entry_id = entry_count + 1

            wordnet = oewn.get(normalized)
            if wordnet:
                seen_oewn.add(normalized)
            pronunciation_us = ipa_us.get(normalized, "")
            pronunciation_uk = ipa_uk.get(normalized, "")
            definition = text(row["definition"])
            translation = text(row["translation"])
            wordnet_definitions = wordnet.get("definitions", []) if wordnet else []
            english_definition = join_values([definition, *wordnet_definitions], limit=5)
            examples = wordnet.get("examples", []) if wordnet else []
            synonyms = ", ".join(unique_values(wordnet.get("synonyms", []) if wordnet else [], limit=12))
            antonyms = ", ".join(unique_values(wordnet.get("antonyms", []) if wordnet else [], limit=12))
            part_of_speech = display_part_of_speech(row["pos"])
            if not part_of_speech and wordnet:
                part_of_speech = text(wordnet.get("part_of_speech"), limit=64)
            frequency = safe_int(row["frq"])
            tags = text(row["tag"], limit=200)
            is_phrase = " " in normalized
            source_names = [SOURCE_ECDICT]
            if pronunciation_us or pronunciation_uk:
                source_names.append(SOURCE_IPA_DICT)
            if wordnet:
                source_names.append(SOURCE_OEWN)

            batch.append(
                (
                    normalized,
                    headword,
                    int(is_phrase),
                    pronunciation_us,
                    pronunciation_uk,
                    part_of_speech,
                    translation,
                    english_definition,
                    join_values(examples, limit=3),
                    synonyms,
                    antonyms,
                    parse_forms(row["exchange"]),
                    frequency,
                    tags,
                    priority(
                        collins=row["collins"],
                        oxford=row["oxford"],
                        frequency=frequency,
                        has_definition=bool(english_definition),
                    ),
                    " · ".join(source_names),
                )
            )
            translation_batch.extend((term, entry_id) for term in translation_terms(translation))
            if is_phrase:
                phrase_batch.extend((token, entry_id) for token in phrase_index_tokens(normalized))
            entry_count += 1
            if len(batch) >= 5_000:
                target_connection.executemany(insert_sql, batch)
                target_connection.executemany(translation_insert_sql, translation_batch)
                target_connection.executemany(phrase_insert_sql, phrase_batch)
                batch.clear()
                translation_batch.clear()
                phrase_batch.clear()
            if entry_count % 100_000 == 0:
                print(f"Processed ECDICT: {entry_count:,} entries", file=sys.stderr)

        if batch:
            target_connection.executemany(insert_sql, batch)
            batch.clear()
        if translation_batch:
            target_connection.executemany(translation_insert_sql, translation_batch)
            translation_batch.clear()
        if phrase_batch:
            target_connection.executemany(phrase_insert_sql, phrase_batch)
            phrase_batch.clear()
        source_cursor.close()

        # Keep valid WordNet lemmas that are absent from ECDICT so uncommon
        # English vocabulary and semantic relations remain searchable.
        for normalized, wordnet in oewn.items():
            if normalized in seen_oewn:
                continue
            headword = normalized
            definitions = wordnet.get("definitions", [])
            synonyms = ", ".join(unique_values(wordnet.get("synonyms", []), limit=12))
            antonyms = ", ".join(unique_values(wordnet.get("antonyms", []), limit=12))
            entry_id = entry_count + 1
            is_phrase = " " in normalized
            part_of_speech = text(wordnet.get("part_of_speech"), limit=64)
            batch.append(
                (
                    normalized,
                    headword,
                    int(is_phrase),
                    "",
                    "",
                    part_of_speech,
                    "",
                    join_values(definitions, limit=5),
                    join_values(wordnet.get("examples", []), limit=3),
                    synonyms,
                    antonyms,
                    "",
                    None,
                    "",
                    priority(collins=None, oxford=None, frequency=None, has_definition=bool(definitions)),
                    SOURCE_OEWN,
                )
            )
            if is_phrase:
                phrase_batch.extend((token, entry_id) for token in phrase_index_tokens(normalized))
            entry_count += 1
            if len(batch) >= 5_000:
                target_connection.executemany(insert_sql, batch)
                target_connection.executemany(phrase_insert_sql, phrase_batch)
                batch.clear()
                phrase_batch.clear()
        if batch:
            target_connection.executemany(insert_sql, batch)
        if translation_batch:
            target_connection.executemany(translation_insert_sql, translation_batch)
        if phrase_batch:
            target_connection.executemany(phrase_insert_sql, phrase_batch)

        # entries_prefix covers exact and prefix lookups because normalized is
        # its leading column. The two WITHOUT ROWID indexes already cover
        # their lookup joins, so extra entry-id indexes would only inflate the
        # bundled resource without helping the read paths.
        target_connection.execute("CREATE INDEX entries_prefix ON entries (normalized, priority DESC, id)")
        target_connection.execute(
            "INSERT INTO metadata (key, value) VALUES (?, ?)",
            ("title", "Study AI Offline English Dictionary"),
        )
        target_connection.execute(
            "INSERT INTO metadata (key, value) VALUES (?, ?)",
            ("entryCount", str(entry_count)),
        )
        target_connection.execute(
            "INSERT INTO metadata (key, value) VALUES (?, ?)",
            ("generatedAt", datetime.now(timezone.utc).isoformat()),
        )
        target_connection.execute(
            "INSERT INTO metadata (key, value) VALUES (?, ?)",
            ("lookupPolicy", "English exact/prefix; Chinese translation exact/prefix; word and phrase only; offline"),
        )
        target_connection.commit()
        target_connection.execute("ANALYZE")
        target_connection.commit()
        target_connection.close()
        target_connection = None

        os.replace(temporary_path, output_path)
        temporary_path = None
        return entry_count, len(oewn)
    finally:
        if source_connection is not None:
            source_connection.close()
        if target_connection is not None:
            target_connection.close()
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except FileNotFoundError:
                pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build SimpleStudy's local dictionary SQLite index")
    parser.add_argument("--ecdict", type=Path, required=True, help="ECDICT stardict.db")
    parser.add_argument("--ipa-us", type=Path, help="IPA-Dict en_US.txt")
    parser.add_argument("--ipa-uk", type=Path, help="IPA-Dict en_UK.txt")
    parser.add_argument("--oewn-jsonl", type=Path, help="Open English WordNet normalized JSONL")
    parser.add_argument("--output", type=Path, required=True, help="Output SQLite path")
    return parser.parse_args()


def main() -> int:
    arguments = parse_args()
    for name, path in (
        ("ECDICT", arguments.ecdict),
        ("IPA-Dict US", arguments.ipa_us),
        ("IPA-Dict UK", arguments.ipa_uk),
        ("Open English WordNet", arguments.oewn_jsonl),
    ):
        if path is not None and not path.is_file():
            raise SystemExit(f"{name} file not found: {path}")

    count, wordnet_count = build_index(
        ecdict_path=arguments.ecdict,
        ipa_us_path=arguments.ipa_us,
        ipa_uk_path=arguments.ipa_uk,
        oewn_path=arguments.oewn_jsonl,
        output_path=arguments.output,
    )
    print(f"Finished: {arguments.output}, {count:,} dictionary entries, {wordnet_count:,} WordNet entries read")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
