import Foundation
import SQLite3

actor LocalDictionarySQLiteIndex {
    nonisolated let package: LocalDictionaryPackage

    private var database: OpaquePointer?
    private let schemaVersion: Int

    init(url: URL) throws {
        var openedDatabase: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &openedDatabase,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard result == SQLITE_OK, let openedDatabase else {
            let message = openedDatabase.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open file"
            if let openedDatabase { sqlite3_close(openedDatabase) }
            throw LocalDictionaryIndexError.cannotOpen(message)
        }

        do {
            sqlite3_busy_timeout(openedDatabase, 500)
            let schemaVersionValue = try Self.scalarString(
                database: openedDatabase,
                sql: "PRAGMA user_version"
            )
            guard let schemaVersion = Int(schemaVersionValue), (schemaVersion == 1 || schemaVersion == 2 || schemaVersion == 3) else {
                throw LocalDictionaryIndexError.unsupportedVersion(schemaVersionValue)
            }

            let title = try Self.metadata(database: openedDatabase, key: "title")
            let entryCount = Int(try Self.metadata(database: openedDatabase, key: "entryCount")) ?? 0
            guard entryCount > 0 else {
                throw LocalDictionaryIndexError.emptyIndex
            }

            self.database = openedDatabase
            self.schemaVersion = schemaVersion
            self.package = LocalDictionaryPackage(
                id: "simple-study-official-dictionary",
                title: title.isEmpty ? "Study AI Offline English Dictionary" : title,
                entries: [],
                entryCount: entryCount,
                sourceSummary: "ECDICT · IPA-Dict · Open English WordNet"
            )
        } catch {
            sqlite3_close(openedDatabase)
            throw error
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func lookup(
        _ query: String,
        maximumTokens: Int = 6,
        maximumResults: Int = 20
    ) throws -> LocalDictionaryLookupResult {
        let normalized = DictionaryTextNormalizer.normalize(query)
        guard !normalized.isEmpty else { return .invalidSelection }
        guard DictionaryTextNormalizer.tokenCount(normalized) <= maximumTokens else {
            return .invalidSelection
        }

        if DictionaryTextNormalizer.containsCJK(normalized) {
            guard DictionaryTextNormalizer.cjkCharacterCount(normalized) <= 16 else {
                return .invalidSelection
            }
            guard schemaVersion >= 2 else { return .noMatch }
            return try lookupTranslation(
                normalized,
                maximumResults: maximumResults
            )
        }

        let exact = try rows(
            sql: """
                SELECT \(Self.columnProjection())
                FROM entries
                WHERE normalized = ?
                ORDER BY priority DESC, CASE WHEN frequency IS NULL THEN 2147483647 ELSE frequency END ASC, id ASC
                LIMIT ?
            """,
            query: normalized,
            limit: maximumResults
        )
        if !exact.isEmpty {
            return .matches(exact + (try lookupPhrases(for: normalized, maximumResults: maximumResults)))
        }

        let escapedPrefix = Self.escapeLikePattern(normalized) + "%"
        let prefix = try rows(
            sql: """
                SELECT \(Self.columnProjection())
                FROM entries
                WHERE normalized LIKE ? ESCAPE '\\'
                ORDER BY priority DESC, CASE WHEN frequency IS NULL THEN 2147483647 ELSE frequency END ASC, id ASC
                LIMIT ?
            """,
            query: escapedPrefix,
            limit: maximumResults
        )
        let phrases = try lookupPhrases(for: normalized, maximumResults: maximumResults)
        let combined = prefix + phrases
        return combined.isEmpty ? .noMatch : .matches(combined)
    }

    private func lookupTranslation(
        _ normalized: String,
        maximumResults: Int
    ) throws -> LocalDictionaryLookupResult {
        let exact = try rows(
            sql: """
                SELECT DISTINCT \(Self.columnProjection(alias: "e"))
                FROM translation_index AS t
                INNER JOIN entries AS e ON e.id = t.entry_id
                WHERE t.normalized = ?
                ORDER BY e.priority DESC, CASE WHEN e.frequency IS NULL THEN 2147483647 ELSE e.frequency END ASC, e.id ASC
                LIMIT ?
            """,
            query: normalized,
            limit: maximumResults
        )
        if !exact.isEmpty {
            return .matches(exact)
        }

        let escapedPrefix = Self.escapeLikePattern(normalized) + "%"
        let prefix = try rows(
            sql: """
                SELECT DISTINCT \(Self.columnProjection(alias: "e"))
                FROM translation_index AS t
                INNER JOIN entries AS e ON e.id = t.entry_id
                WHERE t.normalized LIKE ? ESCAPE '\\'
                ORDER BY e.priority DESC, CASE WHEN e.frequency IS NULL THEN 2147483647 ELSE e.frequency END ASC, e.id ASC
                LIMIT ?
            """,
            query: escapedPrefix,
            limit: maximumResults
        )
        return prefix.isEmpty ? .noMatch : .matches(prefix)
    }

    private func lookupPhrases(for normalized: String, maximumResults: Int) throws -> [LocalDictionaryEntry] {
        guard schemaVersion >= 3,
              DictionaryTextNormalizer.tokenCount(normalized) == 1 else {
            return []
        }

        return try rows(
            sql: """
                SELECT \(Self.columnProjection(alias: "e"))
                FROM phrase_index AS p
                INNER JOIN entries AS e ON e.id = p.entry_id
                WHERE p.token = ?
                ORDER BY e.priority DESC, CASE WHEN e.frequency IS NULL THEN 2147483647 ELSE e.frequency END ASC, e.id ASC
                LIMIT ?
            """,
            query: normalized,
            limit: maximumResults
        )
    }

    private func rows(sql: String, query: String, limit: Int) throws -> [LocalDictionaryEntry] {
        guard let database else { throw LocalDictionaryIndexError.closed }
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw LocalDictionaryIndexError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, query, -1, Self.sqliteTransient)
        sqlite3_bind_int(statement, 2, Int32(max(1, min(limit, 100))))

        var entries: [LocalDictionaryEntry] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else {
                throw LocalDictionaryIndexError.queryFailed(String(cString: sqlite3_errmsg(database)))
            }
            entries.append(Self.entry(from: statement))
        }
        return entries
    }

    private static func entry(from statement: OpaquePointer?) -> LocalDictionaryEntry {
        let rowID = sqlite3_column_int64(statement, 0)
        let headword = columnText(statement, index: 1)
        let pronunciationUS = columnText(statement, index: 3)
        let pronunciationUK = columnText(statement, index: 4)
        return LocalDictionaryEntry(
            id: "public-\(rowID)",
            headword: headword,
            pronunciation: pronunciationUS.isEmpty ? pronunciationUK : pronunciationUS,
            pronunciationUS: pronunciationUS,
            pronunciationUK: pronunciationUK,
            partOfSpeech: columnText(statement, index: 5),
            definition: columnText(statement, index: 6),
            englishDefinition: columnText(statement, index: 7),
            example: columnText(statement, index: 8),
            synonyms: columnText(statement, index: 9),
            antonyms: columnText(statement, index: 10),
            forms: columnText(statement, index: 11),
            frequency: sqlite3_column_type(statement, 12) == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int64(statement, 12)),
            tags: columnText(statement, index: 13),
            sourceName: columnText(statement, index: 14),
            isPhrase: sqlite3_column_int(statement, 2) != 0
        )
    }

    private static func columnProjection(alias: String? = nil) -> String {
        let prefix = alias.map { "\($0)." } ?? ""
        let names = [
            "id", "headword", "is_phrase", "pronunciation_us", "pronunciation_uk",
            "part_of_speech", "translation", "english_definition", "example",
            "synonyms", "antonyms", "forms", "frequency", "tags", "source"
        ]
        return names.map { "\(prefix)\($0)" }.joined(separator: ", ")
    }

    private static func metadata(database: OpaquePointer, key: String) throws -> String {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(
            database,
            "SELECT value FROM metadata WHERE key = ?",
            -1,
            &statement,
            nil
        )
        guard result == SQLITE_OK, let statement else {
            throw LocalDictionaryIndexError.invalidSchema(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LocalDictionaryIndexError.invalidSchema("Missing metadata.\(key)")
        }
        return columnText(statement, index: 0)
    }

    private static func scalarString(database: OpaquePointer, sql: String) throws -> String {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw LocalDictionaryIndexError.invalidSchema(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LocalDictionaryIndexError.invalidSchema("Unable to read database version")
        }
        return columnText(statement, index: 0)
    }

    private static func columnText(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private static func escapeLikePattern(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

enum LocalDictionaryIndexError: LocalizedError {
    case cannotOpen(String)
    case unsupportedVersion(String)
    case emptyIndex
    case closed
    case invalidSchema(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let message): "Unable to open dictionary index: \(message)"
        case .unsupportedVersion(let version): "Unsupported dictionary index version: \(version)"
        case .emptyIndex: "Dictionary index is empty"
        case .closed: "Dictionary index is closed"
        case .invalidSchema(let message): "Invalid dictionary index schema: \(message)"
        case .queryFailed(let message): "Dictionary lookup failed: \(message)"
        }
    }
}
