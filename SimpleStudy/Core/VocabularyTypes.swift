import Foundation

enum VocabularySessionMode: Hashable {
    case all
    case newWords
    case review
}

enum VocabularyRating: String, Codable, CaseIterable, Identifiable {
    case notKnown
    case fuzzy
    case known
    case easy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notKnown: "Again"
        case .fuzzy: "Hard"
        case .known: "Good"
        case .easy: "Easy"
        }
    }

    var systemImage: String {
        switch self {
        case .notKnown: "xmark.circle"
        case .fuzzy: "questionmark.circle"
        case .known: "checkmark.circle"
        case .easy: "bolt.circle"
        }
    }
}

enum VocabularyLearningState: String, Codable, CaseIterable, Identifiable {
    case new
    case learning
    case review
    case mastered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .review: "Due for review"
        case .mastered: "Mastered"
        }
    }
}

enum VocabularyGroupingMode: String, CaseIterable, Identifiable {
    case singleUnit
    case fixedSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .singleUnit: "Keep as one unit"
        case .fixedSize: "Split by group size"
        }
    }
}

/// Canonical JSON source for vocabulary courseware. The decoder accepts a few
/// harmless aliases (groups/words, name/term) so users can import ordinary word
/// lists without hand-editing every field. The exporter always uses the canonical
/// `units` and `items` vocabulary.
struct VocabularyCoursewarePackage: Codable, Equatable {
    let schemaVersion: Int
    let type: String
    let id: String
    let title: String
    let curriculumKey: String?
    let units: [VocabularyUnitPackage]
    /// False when the source had a flat top-level word list and the importer
    /// created a temporary unit so the user can choose how to group it.
    let sourceHasExplicitUnits: Bool

    init(
        schemaVersion: Int = 1,
        type: String = "vocabulary-courseware",
        id: String,
        title: String,
        curriculumKey: String? = nil,
        units: [VocabularyUnitPackage],
        sourceHasExplicitUnits: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.type = type
        self.id = id
        self.title = title
        self.curriculumKey = curriculumKey
        self.units = units
        self.sourceHasExplicitUnits = sourceHasExplicitUnits
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case type
        case id
        case title
        case curriculumKey
        case units
        case groups
        case items
        case words
        case entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "vocabulary-courseware"
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        curriculumKey = try container.decodeIfPresent(String.self, forKey: .curriculumKey)
        if let explicitUnits = try container.decodeIfPresent([VocabularyUnitPackage].self, forKey: .units) {
            units = explicitUnits
            sourceHasExplicitUnits = true
        } else if let explicitGroups = try container.decodeIfPresent([VocabularyUnitPackage].self, forKey: .groups) {
            units = explicitGroups
            sourceHasExplicitUnits = true
        } else {
            let flatItems = try container.decodeIfPresent([VocabularyItemPackage].self, forKey: .items)
                ?? container.decodeIfPresent([VocabularyItemPackage].self, forKey: .words)
                ?? container.decodeIfPresent([VocabularyItemPackage].self, forKey: .entries)
                ?? []
            units = flatItems.isEmpty ? [] : [VocabularyUnitPackage(
                key: "imported-flat-1",
                sequence: 1,
                title: "Ungrouped words",
                unitType: "generated",
                sourceLabel: "Created on import",
                items: flatItems
            )]
            sourceHasExplicitUnits = false
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(type, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(curriculumKey, forKey: .curriculumKey)
        try container.encode(units, forKey: .units)
    }

    static func == (lhs: VocabularyCoursewarePackage, rhs: VocabularyCoursewarePackage) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion &&
        lhs.type == rhs.type &&
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.curriculumKey == rhs.curriculumKey &&
        lhs.units == rhs.units
    }

    func regrouped(for mode: VocabularyGroupingMode, chunkSize: Int = 20) -> VocabularyCoursewarePackage {
        guard !sourceHasExplicitUnits else { return self }
        let flattened = units.flatMap(\.items)
        guard !flattened.isEmpty else { return self }

        let safeChunkSize = max(1, chunkSize)
        let regroupedUnits: [VocabularyUnitPackage]
        switch mode {
        case .singleUnit:
            regroupedUnits = [VocabularyUnitPackage(
                key: "imported-flat-1",
                sequence: 1,
                title: "Ungrouped words",
                unitType: "generated",
                sourceLabel: "Created on import",
                items: flattened
            )]
        case .fixedSize:
            regroupedUnits = stride(from: 0, to: flattened.count, by: safeChunkSize).enumerated().map { index, start in
                let end = min(start + safeChunkSize, flattened.count)
                return VocabularyUnitPackage(
                    key: "imported-flat-\(index + 1)",
                    sequence: index + 1,
                    title: "Unit \(index + 1)",
                    unitType: "generated",
                    sourceLabel: "Split into groups of \(safeChunkSize) words on import",
                    items: Array(flattened[start..<end])
                )
            }
        }

        return VocabularyCoursewarePackage(
            schemaVersion: schemaVersion,
            type: type,
            id: id,
            title: title,
            curriculumKey: curriculumKey,
            units: regroupedUnits,
            sourceHasExplicitUnits: false
        )
    }
}

struct VocabularyUnitPackage: Codable, Equatable, Identifiable {
    let key: String?
    let sequence: Int
    let title: String
    let unitType: String?
    let sourceLabel: String?
    let expectedCount: Int?
    let items: [VocabularyItemPackage]

    var id: String { key ?? "(sequence)-(title)" }

    init(
        key: String? = nil,
        sequence: Int,
        title: String,
        unitType: String? = nil,
        sourceLabel: String? = nil,
        expectedCount: Int? = nil,
        items: [VocabularyItemPackage]
    ) {
        self.key = key
        self.sequence = sequence
        self.title = title
        self.unitType = unitType
        self.sourceLabel = sourceLabel
        self.expectedCount = expectedCount
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case unitKey
        case groupKey
        case sequence
        case title
        case name
        case unitType
        case type
        case sourceLabel
        case expectedCount
        case items
        case words
        case entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key)
            ?? container.decodeIfPresent(String.self, forKey: .unitKey)
            ?? container.decodeIfPresent(String.self, forKey: .groupKey)
        sequence = try container.decodeIfPresent(Int.self, forKey: .sequence) ?? 1
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? ""
        unitType = try container.decodeIfPresent(String.self, forKey: .unitType)
            ?? container.decodeIfPresent(String.self, forKey: .type)
        sourceLabel = try container.decodeIfPresent(String.self, forKey: .sourceLabel)
        expectedCount = try container.decodeIfPresent(Int.self, forKey: .expectedCount)
        items = try container.decodeIfPresent([VocabularyItemPackage].self, forKey: .items)
            ?? container.decodeIfPresent([VocabularyItemPackage].self, forKey: .words)
            ?? container.decodeIfPresent([VocabularyItemPackage].self, forKey: .entries)
            ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(unitType, forKey: .unitType)
        try container.encodeIfPresent(sourceLabel, forKey: .sourceLabel)
        try container.encodeIfPresent(expectedCount, forKey: .expectedCount)
        try container.encode(items, forKey: .items)
    }
}

struct VocabularyItemPackage: Codable, Equatable, Identifiable {
    let key: String?
    let term: String
    let phoneticUK: String
    let phoneticUS: String
    let partOfSpeech: String
    let meaning: String
    let example: String
    let note: String
    let tags: [String]

    var id: String { key ?? term }

    init(
        key: String? = nil,
        term: String,
        phoneticUK: String = "",
        phoneticUS: String = "",
        partOfSpeech: String = "",
        meaning: String = "",
        example: String = "",
        note: String = "",
        tags: [String] = []
    ) {
        self.key = key
        self.term = term
        self.phoneticUK = phoneticUK
        self.phoneticUS = phoneticUS
        self.partOfSpeech = partOfSpeech
        self.meaning = meaning
        self.example = example
        self.note = note
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case itemKey
        case id
        case term
        case word
        case name
        case phoneticUK
        case uk
        case phoneticUS
        case us
        case partOfSpeech
        case pos
        case meaning
        case translation
        case definition
        case example
        case note
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key)
            ?? container.decodeIfPresent(String.self, forKey: .itemKey)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        term = try container.decodeIfPresent(String.self, forKey: .term)
            ?? container.decodeIfPresent(String.self, forKey: .word)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? ""
        phoneticUK = try container.decodeIfPresent(String.self, forKey: .phoneticUK)
            ?? container.decodeIfPresent(String.self, forKey: .uk)
            ?? ""
        phoneticUS = try container.decodeIfPresent(String.self, forKey: .phoneticUS)
            ?? container.decodeIfPresent(String.self, forKey: .us)
            ?? ""
        partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech)
            ?? container.decodeIfPresent(String.self, forKey: .pos)
            ?? ""
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning)
            ?? container.decodeIfPresent(String.self, forKey: .translation)
            ?? container.decodeIfPresent(String.self, forKey: .definition)
            ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encode(term, forKey: .term)
        try container.encode(phoneticUK, forKey: .phoneticUK)
        try container.encode(phoneticUS, forKey: .phoneticUS)
        try container.encode(partOfSpeech, forKey: .partOfSpeech)
        try container.encode(meaning, forKey: .meaning)
        try container.encode(example, forKey: .example)
        try container.encode(note, forKey: .note)
        try container.encode(tags, forKey: .tags)
    }
}

struct VocabularyLearningSnapshot: Equatable {
    let firstLearnedAt: Date?
    let dueAt: Date?
    let intervalSeconds: Double
    let reviewCount: Int
    let lapseCount: Int
    let correctStreak: Int
}

struct VocabularyScheduleResult: Equatable {
    let learningState: VocabularyLearningState
    let firstLearnedAt: Date
    let dueAt: Date
    let intervalSeconds: Double
    let reviewCount: Int
    let lapseCount: Int
    let correctStreak: Int
}

enum VocabularySpacedRepetition {
    static let tenMinutes: TimeInterval = 10 * 60
    static let oneDay: TimeInterval = 24 * 60 * 60
    static let masteryInterval: TimeInterval = 30 * oneDay

    static func schedule(
        snapshot: VocabularyLearningSnapshot,
        rating: VocabularyRating,
        now: Date
    ) -> VocabularyScheduleResult {
        let previousInterval = max(0, snapshot.intervalSeconds)
        let nextInterval: TimeInterval
        switch rating {
        case .notKnown:
            nextInterval = tenMinutes
        case .fuzzy:
            nextInterval = previousInterval > 0
                ? max(tenMinutes, min(oneDay, previousInterval * 0.5))
                : oneDay
        case .known:
            nextInterval = previousInterval > 0
                ? max(3 * oneDay, previousInterval * 2.2)
                : 3 * oneDay
        case .easy:
            nextInterval = previousInterval > 0
                ? max(7 * oneDay, previousInterval * 3.5)
                : 7 * oneDay
        }

        let firstLearnedAt = snapshot.firstLearnedAt ?? now
        let state: VocabularyLearningState
        let correctStreak: Int
        switch rating {
        case .notKnown, .fuzzy:
            state = .learning
            correctStreak = 0
        case .known, .easy:
            state = nextInterval >= masteryInterval ? .mastered : .review
            correctStreak = snapshot.correctStreak + 1
        }

        return VocabularyScheduleResult(
            learningState: state,
            firstLearnedAt: firstLearnedAt,
            dueAt: now.addingTimeInterval(nextInterval),
            intervalSeconds: nextInterval,
            reviewCount: snapshot.reviewCount + 1,
            lapseCount: snapshot.lapseCount + (rating == .notKnown && snapshot.firstLearnedAt != nil ? 1 : 0),
            correctStreak: correctStreak
        )
    }
}

struct VocabularyUnitProgress: Equatable {
    let totalCount: Int
    let firstLearnedCount: Int
    let dueCount: Int

    var isComplete: Bool {
        totalCount > 0 && totalCount == firstLearnedCount
    }
}

enum VocabularyProgressCalculator {
    static func unitProgress(
        items: [VocabularyLearningSnapshot],
        now: Date
    ) -> VocabularyUnitProgress {
        VocabularyUnitProgress(
            totalCount: items.count,
            firstLearnedCount: items.filter { $0.firstLearnedAt != nil }.count,
            dueCount: items.filter { $0.firstLearnedAt == nil || ($0.dueAt ?? .distantFuture) <= now }.count
        )
    }
}
