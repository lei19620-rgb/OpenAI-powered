import Foundation

struct LocalDictionarySense: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let partOfSpeech: String
    let translation: String
    let englishDefinition: String
    let note: String

    init(
        id: String? = nil,
        partOfSpeech: String = "",
        translation: String = "",
        englishDefinition: String = "",
        note: String = ""
    ) {
        let trimmedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnglishDefinition = englishDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackID = DictionaryTextNormalizer.normalize(
            [partOfSpeech, trimmedTranslation, trimmedEnglishDefinition]
                .filter { !$0.trimmed.isEmpty }
                .joined(separator: "-")
        )
        self.id = id?.trimmed.nilIfEmpty ?? (fallbackID.isEmpty ? "sense" : fallbackID)
        self.partOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        self.translation = trimmedTranslation
        self.englishDefinition = trimmedEnglishDefinition
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case partOfSpeech
        case translation
        case englishDefinition
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            partOfSpeech: try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? "",
            translation: try container.decodeIfPresent(String.self, forKey: .translation) ?? "",
            englishDefinition: try container.decodeIfPresent(String.self, forKey: .englishDefinition) ?? "",
            note: try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        )
    }
}

struct LocalDictionaryPhrase: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let expression: String
    let translation: String
    let partOfSpeech: String
    let kind: String

    init(
        id: String? = nil,
        expression: String,
        translation: String = "",
        partOfSpeech: String = "",
        kind: String = "phrase"
    ) {
        let trimmedExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackID = DictionaryTextNormalizer.normalize(trimmedExpression)
        self.id = id?.trimmed.nilIfEmpty ?? (fallbackID.isEmpty ? "phrase" : fallbackID)
        self.expression = trimmedExpression
        self.translation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        self.partOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "phrase"
    }

    var isIdiom: Bool {
        let normalized = kind.lowercased()
        return normalized.contains("idiom") || normalized.contains("\u{4e60}\u{60ef}\u{7528}\u{8bed}")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case expression
        case translation
        case partOfSpeech
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            expression: try container.decodeIfPresent(String.self, forKey: .expression) ?? "",
            translation: try container.decodeIfPresent(String.self, forKey: .translation) ?? "",
            partOfSpeech: try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? "",
            kind: try container.decodeIfPresent(String.self, forKey: .kind) ?? "phrase"
        )
    }
}

struct LocalDictionaryPackage: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let id: String
    let title: String
    let language: String
    let entries: [LocalDictionaryEntry]
    let entryCount: Int?
    let sourceSummary: String?

    init(
        schemaVersion: Int = 1,
        id: String,
        title: String,
        language: String = "en",
        entries: [LocalDictionaryEntry],
        entryCount: Int? = nil,
        sourceSummary: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.language = language
        self.entries = entries
        self.entryCount = entryCount
        self.sourceSummary = sourceSummary
    }

    var totalEntryCount: Int {
        max(entryCount ?? entries.count, entries.count)
    }
}

struct LocalDictionaryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let headword: String
    let pronunciation: String
    let pronunciationUS: String
    let pronunciationUK: String
    let partOfSpeech: String
    let definition: String
    let englishDefinition: String
    let example: String
    let synonyms: String
    let antonyms: String
    let forms: String
    let frequency: Int?
    let tags: String
    let sourceName: String
    let isPhrase: Bool
    let senses: [LocalDictionarySense]
    let phrases: [LocalDictionaryPhrase]
    let phraseKind: String

    init(
        id: String? = nil,
        headword: String,
        pronunciation: String = "",
        pronunciationUS: String = "",
        pronunciationUK: String = "",
        partOfSpeech: String = "",
        definition: String = "",
        englishDefinition: String = "",
        example: String = "",
        synonyms: String = "",
        antonyms: String = "",
        forms: String = "",
        frequency: Int? = nil,
        tags: String = "",
        sourceName: String = "",
        isPhrase: Bool? = nil,
        senses: [LocalDictionarySense] = [],
        phrases: [LocalDictionaryPhrase] = [],
        phraseKind: String = ""
    ) {
        let trimmedHeadword = headword.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? LocalDictionaryEntry.normalized(trimmedHeadword)
        self.headword = trimmedHeadword
        self.pronunciation = pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pronunciationUS = pronunciationUS.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pronunciationUK = pronunciationUK.trimmingCharacters(in: .whitespacesAndNewlines)
        self.partOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        self.definition = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        self.englishDefinition = englishDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        self.example = example.trimmingCharacters(in: .whitespacesAndNewlines)
        self.synonyms = synonyms.trimmingCharacters(in: .whitespacesAndNewlines)
        self.antonyms = antonyms.trimmingCharacters(in: .whitespacesAndNewlines)
        self.forms = forms.trimmingCharacters(in: .whitespacesAndNewlines)
        self.frequency = frequency
        self.tags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIsPhrase = isPhrase ?? (trimmedHeadword.split(whereSeparator: { $0.isWhitespace }).count > 1)
        self.isPhrase = resolvedIsPhrase
        self.senses = senses
        self.phrases = phrases
        self.phraseKind = phraseKind.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (resolvedIsPhrase ? "phrase" : "word")
    }

    var primaryPronunciation: String {
        if !pronunciationUS.isEmpty { return pronunciationUS }
        if !pronunciationUK.isEmpty { return pronunciationUK }
        return pronunciation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case headword
        case word
        case phrase
        case pronunciation
        case phonetic
        case pronunciationUS
        case pronunciationUK
        case partOfSpeech
        case pos
        case definition
        case meaning
        case englishDefinition
        case englishMeaning
        case example
        case synonyms
        case antonyms
        case forms
        case frequency
        case tags
        case sourceName
        case isPhrase
        case senses
        case phrases
        case phraseKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedHeadword = try container.decodeIfPresent(String.self, forKey: .headword)
            ?? container.decodeIfPresent(String.self, forKey: .word)
            ?? container.decodeIfPresent(String.self, forKey: .phrase)
            ?? ""
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            headword: decodedHeadword,
            pronunciation: try container.decodeIfPresent(String.self, forKey: .pronunciation)
                ?? container.decodeIfPresent(String.self, forKey: .phonetic)
                ?? "",
            pronunciationUS: try container.decodeIfPresent(String.self, forKey: .pronunciationUS) ?? "",
            pronunciationUK: try container.decodeIfPresent(String.self, forKey: .pronunciationUK) ?? "",
            partOfSpeech: try container.decodeIfPresent(String.self, forKey: .partOfSpeech)
                ?? container.decodeIfPresent(String.self, forKey: .pos)
                ?? "",
            definition: try container.decodeIfPresent(String.self, forKey: .definition)
                ?? container.decodeIfPresent(String.self, forKey: .meaning)
                ?? "",
            englishDefinition: try container.decodeIfPresent(String.self, forKey: .englishDefinition)
                ?? container.decodeIfPresent(String.self, forKey: .englishMeaning)
                ?? "",
            example: try container.decodeIfPresent(String.self, forKey: .example) ?? "",
            synonyms: try container.decodeIfPresent(String.self, forKey: .synonyms) ?? "",
            antonyms: try container.decodeIfPresent(String.self, forKey: .antonyms) ?? "",
            forms: try container.decodeIfPresent(String.self, forKey: .forms) ?? "",
            frequency: try container.decodeIfPresent(Int.self, forKey: .frequency),
            tags: try container.decodeIfPresent(String.self, forKey: .tags) ?? "",
            sourceName: try container.decodeIfPresent(String.self, forKey: .sourceName) ?? "",
            isPhrase: try container.decodeIfPresent(Bool.self, forKey: .isPhrase),
            senses: try container.decodeIfPresent([LocalDictionarySense].self, forKey: .senses) ?? [],
            phrases: try container.decodeIfPresent([LocalDictionaryPhrase].self, forKey: .phrases) ?? [],
            phraseKind: try container.decodeIfPresent(String.self, forKey: .phraseKind) ?? ""
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(headword, forKey: .headword)
        try container.encode(pronunciation, forKey: .pronunciation)
        try container.encode(pronunciationUS, forKey: .pronunciationUS)
        try container.encode(pronunciationUK, forKey: .pronunciationUK)
        try container.encode(partOfSpeech, forKey: .partOfSpeech)
        try container.encode(definition, forKey: .definition)
        try container.encode(englishDefinition, forKey: .englishDefinition)
        try container.encode(example, forKey: .example)
        try container.encode(synonyms, forKey: .synonyms)
        try container.encode(antonyms, forKey: .antonyms)
        try container.encode(forms, forKey: .forms)
        try container.encodeIfPresent(frequency, forKey: .frequency)
        try container.encode(tags, forKey: .tags)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(isPhrase, forKey: .isPhrase)
        try container.encode(senses, forKey: .senses)
        try container.encode(phrases, forKey: .phrases)
        try container.encode(phraseKind, forKey: .phraseKind)
    }

    private static func normalized(_ value: String) -> String {
        DictionaryTextNormalizer.normalize(value)
    }
}

enum LocalDictionarySenseParser {
    static func displayPartOfSpeech(_ value: String) -> String {
        normalizedPartOfSpeech(value)
    }

    static func senses(for entry: LocalDictionaryEntry) -> [LocalDictionarySense] {
        if !entry.senses.isEmpty {
            return entry.senses
        }

        let translations = sections(from: entry.definition, splitChineseList: true)
        let englishDefinitions = sections(from: entry.englishDefinition, splitChineseList: false)
        let count = max(translations.count, englishDefinitions.count)
        guard count > 0 else { return [] }

        var result: [LocalDictionarySense] = []
        for index in 0..<min(count, 24) {
            let translation = index < translations.count ? translations[index] : ParsedSection()
            let english = index < englishDefinitions.count ? englishDefinitions[index] : ParsedSection()
            let chineseText = translation.content
            let englishText = english.content
            guard !chineseText.isEmpty || !englishText.isEmpty else { continue }

            result.append(LocalDictionarySense(
                id: "fallback-\(index + 1)",
                partOfSpeech: normalizedPartOfSpeech(
                    translation.partOfSpeech.nilIfEmpty
                        ?? english.partOfSpeech.nilIfEmpty
                        ?? entry.partOfSpeech
                ),
                translation: chineseText,
                englishDefinition: englishText,
                note: translation.note
            ))
        }
        return result
    }

    private struct ParsedSection {
        let partOfSpeech: String
        let content: String
        let note: String

        init(partOfSpeech: String = "", content: String = "", note: String = "") {
            self.partOfSpeech = partOfSpeech
            self.content = content
            self.note = note
        }
    }

    private static func sections(from value: String, splitChineseList: Bool) -> [ParsedSection] {
        var result: [ParsedSection] = []
        for rawLine in value.split(whereSeparator: { $0.isNewline }) {
            var line = String(rawLine).trimmed
            guard !line.isEmpty else { continue }

            var notes: [String] = []
            while line.first == "[", let closingIndex = line.firstIndex(of: "]") {
                let note = String(line[line.index(after: line.startIndex)..<closingIndex]).trimmed
                if !note.isEmpty { notes.append(note) }
                line = String(line[line.index(after: closingIndex)...]).trimmed
            }

            var partOfSpeech = ""
            if let dotIndex = line.firstIndex(of: ".") {
                let candidate = String(line[..<dotIndex])
                if !candidate.isEmpty,
                   candidate.count <= 8,
                   candidate.allSatisfy({ $0.isLetter }) {
                    partOfSpeech = "\(candidate)."
                    line = String(line[line.index(after: dotIndex)...]).trimmed
                }
            }
            guard !line.isEmpty else { continue }

            let values: [String]
            if splitChineseList && DictionaryTextNormalizer.containsCJK(line) {
                values = line
                    .split(whereSeparator: { character in
                        character == "," || character == "，" || character == ";" || character == "；"
                    })
                    .map { String($0).trimmed }
                    .filter { !$0.isEmpty }
            } else {
                values = [line]
            }
            result.append(contentsOf: values.map {
                ParsedSection(partOfSpeech: partOfSpeech, content: $0, note: notes.joined(separator: ", "))
            })
        }
        return result
    }

    private static func normalizedPartOfSpeech(_ value: String) -> String {
        let trimmed = value.trimmed
        guard trimmed.contains(":"), trimmed.contains(where: { $0.isLetter }) else {
            return trimmed
        }

        let labels = trimmed
            .split(separator: "/")
            .compactMap { token -> String? in
                let code = token.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
                let mapped: String
                switch code.lowercased() {
                case "n": mapped = "n."
                case "v", "vt", "vi": mapped = "v."
                case "a", "j": mapped = "adj."
                case "ad", "r": mapped = "adv."
                case "prep": mapped = "prep."
                case "conj": mapped = "conj."
                case "pron": mapped = "pron."
                case "num": mapped = "num."
                case "art": mapped = "art."
                case "aux": mapped = "aux."
                default: mapped = code.isEmpty ? "" : "\(code)."
                }
                return mapped.nilIfEmpty
            }

        var unique: [String] = []
        for label in labels where !unique.contains(label) {
            unique.append(label)
        }
        return unique.joined(separator: " / ")
    }
}

enum DictionaryTextNormalizer {
    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?()[]{}\"“”…")

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "＇", with: "'")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: edgePunctuation) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func tokenCount(_ value: String) -> Int {
        normalize(value).split(separator: " ").count
    }

    static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            isCJKScalar(scalar.value)
        }
    }

    static func cjkCharacterCount(_ value: String) -> Int {
        value.unicodeScalars.reduce(into: 0) { count, scalar in
            if isCJKScalar(scalar.value) { count += 1 }
        }
    }

    private static func isCJKScalar(_ value: UInt32) -> Bool {
        (0x3400...0x4DBF).contains(value)
            || (0x4E00...0x9FFF).contains(value)
            || (0xF900...0xFAFF).contains(value)
    }
}

/// Converts a system text selection into a safe local dictionary query.
///
/// Selection-based lookup intentionally accepts only a short word or phrase.
/// The full-sentence case stays out of the floating lookup flow, while the
/// regular dictionary search can still explain an invalid selection when the
/// user explicitly searches.
enum DictionarySelectionQuery {
    static let maximumTokens = 6
    static let maximumCJKCharacters = 16

    static func normalized(from selection: String?) -> String? {
        guard let selection else { return nil }
        let normalized = DictionaryTextNormalizer.normalize(selection)
        guard !normalized.isEmpty,
              DictionaryTextNormalizer.tokenCount(normalized) <= maximumTokens,
              normalized.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return nil
        }

        if DictionaryTextNormalizer.containsCJK(normalized),
           DictionaryTextNormalizer.cjkCharacterCount(normalized) > maximumCJKCharacters {
            return nil
        }
        return normalized
    }
}

enum LocalDictionaryImportError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidJSON(String)
    case unsupportedVersion(Int)
    case emptyIdentifier
    case emptyTitle
    case noEntries
    case tooManyEntries
    case duplicateEntryID(String)
    case invalidEntry(index: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "Dictionary packages must not exceed 50 MB"
        case .invalidJSON(let reason): "Invalid dictionary JSON: \(reason)"
        case .unsupportedVersion(let version): "Unsupported schema version \(version); only version 1 is supported"
        case .emptyIdentifier: "Dictionary ID is required"
        case .emptyTitle: "Dictionary title is required"
        case .noEntries: "A dictionary needs at least one word or phrase"
        case .tooManyEntries: "Dictionary packages support up to 200,000 entries"
        case .duplicateEntryID(let id): "Duplicate entry ID: \(id)"
        case .invalidEntry(let index, let reason): "Dictionary entry \(index + 1): \(reason)"
        }
    }
}

enum LocalDictionaryPackageService {
    static let maximumFileSize = 50_000_000
    static let maximumEntries = 200_000

    static func decodeAndValidate(_ data: Data) throws -> LocalDictionaryPackage {
        guard data.count <= maximumFileSize else { throw LocalDictionaryImportError.fileTooLarge }

        let package: LocalDictionaryPackage
        do {
            package = try JSONCoding.decoder.decode(LocalDictionaryPackage.self, from: data)
        } catch {
            throw LocalDictionaryImportError.invalidJSON(error.localizedDescription)
        }

        guard package.schemaVersion == 1 else {
            throw LocalDictionaryImportError.unsupportedVersion(package.schemaVersion)
        }
        guard !package.id.trimmed.isEmpty, package.id.count <= 160 else {
            throw LocalDictionaryImportError.emptyIdentifier
        }
        guard !package.title.trimmed.isEmpty, package.title.count <= 160 else {
            throw LocalDictionaryImportError.emptyTitle
        }
        guard !package.entries.isEmpty else { throw LocalDictionaryImportError.noEntries }
        guard package.entries.count <= maximumEntries else { throw LocalDictionaryImportError.tooManyEntries }

        var IDs = Set<String>()
        for (index, entry) in package.entries.enumerated() {
            guard !entry.headword.trimmed.isEmpty, entry.headword.count <= 500 else {
                throw LocalDictionaryImportError.invalidEntry(index: index, reason: "Words and phrases must contain 1–500 characters")
            }
            guard entry.definition.count <= 20_000,
                  entry.englishDefinition.count <= 50_000,
                  entry.example.count <= 10_000,
                  entry.synonyms.count <= 5_000,
                  entry.antonyms.count <= 5_000,
                  entry.forms.count <= 5_000,
                  entry.senses.count <= 64,
                  entry.phrases.count <= 256,
                  entry.senses.allSatisfy({ $0.translation.count <= 20_000 && $0.englishDefinition.count <= 50_000 }),
                  entry.phrases.allSatisfy({ $0.expression.count <= 500 && $0.translation.count <= 20_000 }) else {
                throw LocalDictionaryImportError.invalidEntry(index: index, reason: "Definition or example is too long")
            }
            guard IDs.insert(entry.id).inserted else {
                throw LocalDictionaryImportError.duplicateEntryID(entry.id)
            }
        }
        return package
    }

    static func exportData(for package: LocalDictionaryPackage) throws -> Data {
        try JSONCoding.encoder.encode(package)
    }

    static var examplePackage: LocalDictionaryPackage {
        LocalDictionaryPackage(
            id: "dictionary-example",
            title: "Example Dictionary",
            entries: [
                LocalDictionaryEntry(
                    headword: "review",
                    pronunciation: "/rɪˈvjuː/",
                    pronunciationUS: "/rɪˈvjuː/",
                    pronunciationUK: "/rɪˈvjuː/",
                    partOfSpeech: "v./n.",
                    definition: "Study again; evaluate",
                    englishDefinition: "to study something again; a critical evaluation",
                    example: "I review the words every evening.",
                    senses: [
                        LocalDictionarySense(
                            id: "review-v",
                            partOfSpeech: "v.",
                            translation: "\u{590d}\u{4e60}",
                            englishDefinition: "to study something again"
                        ),
                        LocalDictionarySense(
                            id: "review-n",
                            partOfSpeech: "n.",
                            translation: "\u{8bc4}\u{8bba}\u{FF1B}\u{5ba1}\u{67e5}",
                            englishDefinition: "a critical evaluation"
                        )
                    ],
                    phrases: [
                        LocalDictionaryPhrase(
                            id: "review-board",
                            expression: "review board",
                            translation: "\u{5ba1}\u{67e5}\u{59d4}\u{5458}\u{4f1a}",
                            partOfSpeech: "n."
                        )
                    ]
                ),
                LocalDictionaryEntry(
                    headword: "review board",
                    partOfSpeech: "n.",
                    definition: "\u{5ba1}\u{67e5}\u{59d4}\u{5458}\u{4f1a}",
                    example: "The review board read the report."
                )
            ]
        )
    }

    static func exampleData() throws -> Data {
        try JSONCoding.encoder.encode(examplePackage)
    }
}

enum LocalDictionaryLookupResult: Equatable {
    case invalidSelection
    case noMatch
    case matches([LocalDictionaryEntry])

    var matchesCount: Int {
        if case .matches(let entries) = self { return entries.count }
        return 0
    }
}

enum LocalDictionaryLookup {
    static func result(
        for query: String,
        entries: [LocalDictionaryEntry],
        maximumTokens: Int = 6
    ) -> LocalDictionaryLookupResult {
        let normalizedQuery = DictionaryTextNormalizer.normalize(query)
        guard !normalizedQuery.isEmpty else { return .invalidSelection }
        let tokenCount = DictionaryTextNormalizer.tokenCount(normalizedQuery)
        guard tokenCount <= maximumTokens else { return .invalidSelection }

        let isTranslationQuery = DictionaryTextNormalizer.containsCJK(normalizedQuery)
        if isTranslationQuery,
           DictionaryTextNormalizer.cjkCharacterCount(normalizedQuery) > 16 {
            return .invalidSelection
        }

        let exact = entries.filter { entry in
            if isTranslationQuery {
                return DictionaryTextNormalizer.normalize(entry.definition).contains(normalizedQuery)
            }
            return DictionaryTextNormalizer.normalize(entry.headword) == normalizedQuery
        }
        if !exact.isEmpty {
            return .matches(exact + phraseEntries(for: normalizedQuery, entries: entries, isTranslationQuery: isTranslationQuery))
        }

        let prefix = entries.filter { entry in
            if isTranslationQuery {
                return DictionaryTextNormalizer.normalize(entry.definition).contains(normalizedQuery)
            }
            return DictionaryTextNormalizer.normalize(entry.headword).hasPrefix(normalizedQuery)
        }
        let phrases = phraseEntries(for: normalizedQuery, entries: entries, isTranslationQuery: isTranslationQuery)
        let combined = Array(prefix.prefix(20)) + phrases
        return combined.isEmpty ? .noMatch : .matches(combined)
    }

    private static func phraseEntries(
        for normalizedQuery: String,
        entries: [LocalDictionaryEntry],
        isTranslationQuery: Bool
    ) -> [LocalDictionaryEntry] {
        guard !isTranslationQuery,
              DictionaryTextNormalizer.tokenCount(normalizedQuery) == 1 else {
            return []
        }

        return Array(entries.filter { entry in
            guard entry.isPhrase else { return false }
            return DictionaryTextNormalizer.normalize(entry.headword)
                .split(separator: " ")
                .contains { String($0) == normalizedQuery }
        }.prefix(20))
    }

    static func merged(
        _ preferred: LocalDictionaryLookupResult,
        _ fallback: LocalDictionaryLookupResult,
        maximumResults: Int = 40
    ) -> LocalDictionaryLookupResult {
        switch (preferred, fallback) {
        case (.invalidSelection, _), (_, .invalidSelection):
            return .invalidSelection
        case (.noMatch, .noMatch):
            return .noMatch
        case (.matches(let preferredEntries), .matches(let fallbackEntries)):
            var seen = Set<String>()
            let combined = (preferredEntries + fallbackEntries).filter { entry in
                seen.insert(entry.id).inserted
            }
            return combined.isEmpty ? .noMatch : .matches(Array(combined.prefix(maximumResults)))
        case (.matches(let entries), .noMatch), (.noMatch, .matches(let entries)):
            return .matches(Array(entries.prefix(maximumResults)))
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
