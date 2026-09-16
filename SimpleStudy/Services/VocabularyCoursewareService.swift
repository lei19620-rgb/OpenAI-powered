import Foundation
import SwiftData

struct VocabularyImportSummary: Equatable {
    let coursewareID: UUID
    let coursewareTitle: String
    let unitCount: Int
    let itemCount: Int
    let updatedExistingCourseware: Bool
}

enum VocabularyImportError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidJSON(String)
    case unsupportedVersion(Int)
    case invalidType
    case emptyIdentifier
    case emptyTitle
    case noUnits
    case tooManyUnits
    case duplicateUnitKey(String)
    case invalidUnit(index: Int, reason: String)
    case tooManyItems
    case duplicateItemKey(unit: String, key: String)
    case invalidItem(unit: String, index: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "Word collections must not exceed 50 MB"
        case .invalidJSON(let reason):
            "Invalid word collection JSON: \(reason)"
        case .unsupportedVersion(let version):
            "Unsupported schema version \(version); only version 1 is supported"
        case .invalidType:
            "File type must be vocabulary-courseware"
        case .emptyIdentifier:
            "Collection ID must not be empty"
        case .emptyTitle:
            "Collection title must not be empty"
        case .noUnits:
            "A collection needs at least one unit"
        case .tooManyUnits:
            "A collection supports up to 500 units"
        case .duplicateUnitKey(let key):
            "Duplicate unit key: \(key)"
        case .invalidUnit(let index, let reason):
            "Unit \(index + 1): \(reason)"
        case .tooManyItems:
            "A collection supports up to 100,000 entries"
        case .duplicateItemKey(let unit, let key):
            "Duplicate entry key in unit \(unit): \(key)"
        case .invalidItem(let unit, let index, let reason):
            "Unit \(unit), entry \(index + 1): \(reason)"
        }
    }
}

enum VocabularyCoursewareService {
    static let maximumFileSize = 50_000_000
    static let maximumUnits = 500
    static let maximumItems = 100_000

    static func decodeAndValidate(_ data: Data) throws -> VocabularyCoursewarePackage {
        guard data.count <= maximumFileSize else { throw VocabularyImportError.fileTooLarge }

        let package: VocabularyCoursewarePackage
        do {
            package = try JSONCoding.decoder.decode(VocabularyCoursewarePackage.self, from: data)
        } catch {
            throw VocabularyImportError.invalidJSON(error.localizedDescription)
        }

        guard package.schemaVersion == 1 else {
            throw VocabularyImportError.unsupportedVersion(package.schemaVersion)
        }
        guard package.type == "vocabulary-courseware" else {
            throw VocabularyImportError.invalidType
        }
        guard !package.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              package.id.count <= 160 else {
            throw VocabularyImportError.emptyIdentifier
        }
        guard !package.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              package.title.count <= 160 else {
            throw VocabularyImportError.emptyTitle
        }
        guard !package.units.isEmpty else { throw VocabularyImportError.noUnits }
        guard package.units.count <= maximumUnits else { throw VocabularyImportError.tooManyUnits }

        var unitKeys = Set<String>()
        var totalItems = 0
        for (unitIndex, unit) in package.units.enumerated() {
            let unitKey = resolvedUnitKey(unit, index: unitIndex)
            guard unit.sequence > 0 else {
                throw VocabularyImportError.invalidUnit(index: unitIndex, reason: "sequence must be greater than 0")
            }
            guard !unit.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  unit.title.count <= 160 else {
                throw VocabularyImportError.invalidUnit(index: unitIndex, reason: "The title must contain 1–160 characters")
            }
            guard unit.items.count > 0 else {
                throw VocabularyImportError.invalidUnit(index: unitIndex, reason: "At least one entry is required")
            }
            guard unit.items.count <= maximumItems else {
                throw VocabularyImportError.invalidUnit(index: unitIndex, reason: "This unit contains too many entries")
            }
            if let expectedCount = unit.expectedCount, expectedCount < 0 {
                throw VocabularyImportError.invalidUnit(index: unitIndex, reason: "expectedCount must not be negative")
            }
            guard unitKeys.insert(normalizedIdentity(unitKey)).inserted else {
                throw VocabularyImportError.duplicateUnitKey(unitKey)
            }

            var itemKeys = Set<String>()
            for (itemIndex, item) in unit.items.enumerated() {
                let itemKey = resolvedItemKey(item, index: itemIndex)
                let trimmedTerm = item.term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTerm.isEmpty, trimmedTerm.count <= 500 else {
                    throw VocabularyImportError.invalidItem(
                        unit: unit.title,
                        index: itemIndex,
                        reason: "term must contain 1–500 characters"
                    )
                }
                guard item.meaning.count <= 5_000,
                      item.example.count <= 5_000,
                      item.note.count <= 5_000 else {
                    throw VocabularyImportError.invalidItem(
                        unit: unit.title,
                        index: itemIndex,
                        reason: "Definitions, examples, and notes must not exceed 5,000 characters"
                    )
                }
                guard itemKeys.insert(normalizedIdentity(itemKey)).inserted else {
                    throw VocabularyImportError.duplicateItemKey(unit: unit.title, key: itemKey)
                }
                totalItems += 1
                guard totalItems <= maximumItems else { throw VocabularyImportError.tooManyItems }
            }
        }

        return package
    }

    static func exportData(for package: VocabularyCoursewarePackage) throws -> Data {
        try prettyEncoder.encode(package)
    }

    static var examplePackage: VocabularyCoursewarePackage {
        VocabularyCoursewarePackage(
            id: "example-courseware",
            title: "Essential vocabulary example",
            curriculumKey: "english-foundation",
            units: [
                VocabularyUnitPackage(
                    key: "unit-01",
                    sequence: 1,
                    title: "Group 1 · Everyday actions",
                    unitType: "group",
                    sourceLabel: "Example",
                    items: [
                        VocabularyItemPackage(
                            key: "prepare",
                            term: "prepare",
                            phoneticUK: "/prɪˈpeə(r)/",
                            phoneticUS: "/prɪˈper/",
                            partOfSpeech: "v.",
                            meaning: "Make ready; get ready",
                            example: "I prepare my notes before class.",
                            tags: ["Essential", "Action"]
                        ),
                        VocabularyItemPackage(
                            key: "review",
                            term: "review",
                            partOfSpeech: "v./n.",
                            meaning: "Study again; evaluate",
                            example: "I review the words every evening.",
                            tags: ["Essential", "Study"]
                        )
                    ]
                ),
                VocabularyUnitPackage(
                    key: "unit-02",
                    sequence: 2,
                    title: "Group 2 · Learning expressions",
                    unitType: "group",
                    items: [
                        VocabularyItemPackage(
                            key: "understand",
                            term: "understand",
                            partOfSpeech: "v.",
                            meaning: "Grasp the meaning; comprehend",
                            example: "I understand the sentence now.",
                            tags: ["Essential", "Understanding"]
                        )
                    ]
                )
            ]
        )
    }

    static func exampleData() throws -> Data {
        try exportData(for: examplePackage)
    }

    @MainActor
    static func importPackage(
        _ package: VocabularyCoursewarePackage,
        sourceFileName: String,
        context: ModelContext
    ) throws -> VocabularyImportSummary {
        let trimmedCoursewareKey = package.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let coursewares = try context.fetch(FetchDescriptor<VocabularyCoursewareRecord>())
        let existingCourseware = coursewares.first { $0.coursewareKey == trimmedCoursewareKey }
        let courseware = existingCourseware ?? VocabularyCoursewareRecord(
            coursewareKey: trimmedCoursewareKey,
            title: package.title.trimmingCharacters(in: .whitespacesAndNewlines),
            curriculumKey: package.curriculumKey?.trimmedNil,
            sourceFileName: sourceFileName,
            sourceFormat: "json"
        )
        if existingCourseware == nil { context.insert(courseware) }

        courseware.title = package.title.trimmingCharacters(in: .whitespacesAndNewlines)
        courseware.curriculumKey = package.curriculumKey?.trimmedNil
        courseware.sourceFileName = sourceFileName
        courseware.sourceFormat = "json"
        courseware.updatedAt = Date()

        let allUnits = try context.fetch(FetchDescriptor<VocabularyUnitRecord>())
        let allItems = try context.fetch(FetchDescriptor<VocabularyItemRecord>())
        let existingUnits = allUnits.filter { $0.coursewareID == courseware.id }
        let existingItems = allItems.filter { $0.coursewareID == courseware.id }
        var activeUnitIDs = Set<UUID>()
        var activeItemIDs = Set<UUID>()
        var importedUnits: [VocabularyUnitRecord] = []
        var importedItems: [VocabularyItemRecord] = []

        for (unitIndex, sourceUnit) in package.units.enumerated() {
            let unitKey = resolvedUnitKey(sourceUnit, index: unitIndex)
            let unit = existingUnits.first { $0.unitKey == unitKey }
                ?? VocabularyUnitRecord(
                    coursewareID: courseware.id,
                    unitKey: unitKey,
                    sequence: sourceUnit.sequence,
                    title: sourceUnit.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    unitType: sourceUnit.unitType?.trimmedNil ?? "unit",
                    sourceLabel: sourceUnit.sourceLabel?.trimmedNil ?? "",
                    expectedCount: sourceUnit.expectedCount
                )
            if unit.modelContext == nil { context.insert(unit) }

            unit.coursewareID = courseware.id
            unit.unitKey = unitKey
            unit.sequence = sourceUnit.sequence
            unit.title = sourceUnit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            unit.unitType = sourceUnit.unitType?.trimmedNil ?? "unit"
            unit.sourceLabel = sourceUnit.sourceLabel?.trimmedNil ?? ""
            unit.expectedCount = sourceUnit.expectedCount
            unit.isActive = true
            unit.updatedAt = Date()
            activeUnitIDs.insert(unit.id)
            importedUnits.append(unit)

            let existingUnitItems = existingItems.filter { $0.unitID == unit.id }
            for (itemIndex, sourceItem) in sourceUnit.items.enumerated() {
                let itemKey = resolvedItemKey(sourceItem, index: itemIndex)
                let item = existingUnitItems.first { $0.sourceItemKey == itemKey }
                    ?? VocabularyItemRecord(
                        coursewareID: courseware.id,
                        unitID: unit.id,
                        sourceItemKey: itemKey,
                        order: itemIndex,
                        term: sourceItem.term.trimmed,
                        phoneticUK: sourceItem.phoneticUK.trimmed,
                        phoneticUS: sourceItem.phoneticUS.trimmed,
                        partOfSpeech: sourceItem.partOfSpeech.trimmed,
                        meaning: sourceItem.meaning.trimmed,
                        example: sourceItem.example.trimmed,
                        note: sourceItem.note.trimmed,
                        tags: sourceItem.tags.map(\.trimmed).filter { !$0.isEmpty }
                    )
                if item.modelContext == nil { context.insert(item) }

                item.coursewareID = courseware.id
                item.unitID = unit.id
                item.sourceItemKey = itemKey
                item.order = itemIndex
                item.term = sourceItem.term.trimmed
                item.phoneticUK = sourceItem.phoneticUK.trimmed
                item.phoneticUS = sourceItem.phoneticUS.trimmed
                item.partOfSpeech = sourceItem.partOfSpeech.trimmed
                item.meaning = sourceItem.meaning.trimmed
                item.example = sourceItem.example.trimmed
                item.note = sourceItem.note.trimmed
                item.tags = sourceItem.tags.map(\.trimmed).filter { !$0.isEmpty }
                item.isActive = true
                item.updatedAt = Date()
                activeItemIDs.insert(item.id)
                importedItems.append(item)
            }
        }

        for unit in existingUnits where !activeUnitIDs.contains(unit.id) {
            unit.isActive = false
            unit.updatedAt = Date()
        }
        for item in existingItems where !activeItemIDs.contains(item.id) {
            item.isActive = false
            item.updatedAt = Date()
        }

        // Calculate only after the new membership is known. Removed words must
        // not block completion, and added words must reopen the unit progress.
        let itemsByUnit = Dictionary(grouping: importedItems, by: \.unitID)
        for unit in importedUnits {
            let progress = VocabularyProgressCalculator.unitProgress(
                items: (itemsByUnit[unit.id] ?? []).map(\.learningSnapshot), now: Date()
            )
            unit.completedAt = progress.isComplete ? (unit.completedAt ?? Date()) : nil
        }
        courseware.completedAt = !importedUnits.isEmpty && importedUnits.allSatisfy { $0.completedAt != nil }
            ? (courseware.completedAt ?? Date())
            : nil

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return VocabularyImportSummary(
            coursewareID: courseware.id,
            coursewareTitle: courseware.title,
            unitCount: package.units.count,
            itemCount: package.units.reduce(0) { $0 + $1.items.count },
            updatedExistingCourseware: existingCourseware != nil
        )
    }

    static func resolvedUnitKey(_ unit: VocabularyUnitPackage, index: Int) -> String {
        let value = unit.key?.trimmedNil
        return value ?? "unit-\(unit.sequence)-\(index + 1)"
    }

    static func resolvedItemKey(_ item: VocabularyItemPackage, index: Int) -> String {
        let value = item.key?.trimmedNil
        return value ?? "\(normalizedIdentity(item.term))-\(index + 1)"
    }

    private static func normalizedIdentity(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

@MainActor
enum VocabularyReviewService {
    static func items(for unitID: UUID, context: ModelContext) throws -> [VocabularyItemRecord] {
        try context.fetch(FetchDescriptor<VocabularyItemRecord>())
            .filter { $0.unitID == unitID && $0.isActive }
            .sorted { lhs, rhs in
                if lhs.order == rhs.order { return lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending }
                return lhs.order < rhs.order
            }
    }

    static func itemsDue(in coursewareID: UUID?, unitID: UUID?, context: ModelContext, now: Date = Date()) throws -> [VocabularyItemRecord] {
        let unitOrder = Dictionary(try context.fetch(FetchDescriptor<VocabularyUnitRecord>()).map { ($0.id, $0.sequence) }, uniquingKeysWith: { first, _ in first })
        return try context.fetch(FetchDescriptor<VocabularyItemRecord>())
            .filter { item in
                guard item.isActive else { return false }
                if let coursewareID, item.coursewareID != coursewareID { return false }
                if let unitID, item.unitID != unitID { return false }
                return item.firstLearnedAt == nil || (item.dueAt ?? .distantFuture) <= now
            }
            .sorted { lhs, rhs in
                if lhs.coursewareID == rhs.coursewareID && lhs.unitID == rhs.unitID && lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                if lhs.coursewareID != rhs.coursewareID { return lhs.coursewareID.uuidString < rhs.coursewareID.uuidString }
                if lhs.unitID != rhs.unitID {
                    let left = unitOrder[lhs.unitID] ?? Int.max
                    let right = unitOrder[rhs.unitID] ?? Int.max
                    return left == right ? lhs.unitID.uuidString < rhs.unitID.uuidString : left < right
                }
                return lhs.order < rhs.order
            }
    }

    static func progress(for unit: VocabularyUnitRecord, context: ModelContext, now: Date = Date()) throws -> VocabularyUnitProgress {
        let items = try items(for: unit.id, context: context)
        return VocabularyProgressCalculator.unitProgress(
            items: items.map(\.learningSnapshot),
            now: now
        )
    }

    static func record(
        rating: VocabularyRating,
        for item: VocabularyItemRecord,
        context: ModelContext,
        now: Date = Date()
    ) throws -> VocabularyReviewOutcome {
        let units = try context.fetch(FetchDescriptor<VocabularyUnitRecord>())
        guard item.isActive, let unit = units.first(where: { $0.id == item.unitID && $0.isActive }) else {
            throw VocabularyReviewError.missingUnit
        }
        let coursewares = try context.fetch(FetchDescriptor<VocabularyCoursewareRecord>())
        guard let courseware = coursewares.first(where: { $0.id == item.coursewareID }) else {
            throw VocabularyReviewError.missingCourseware
        }
        let unitItems = try items(for: unit.id, context: context)
        let snapshot = item.learningSnapshot
        let schedule = VocabularySpacedRepetition.schedule(snapshot: snapshot, rating: rating, now: now)

        item.learningState = schedule.learningState
        item.firstLearnedAt = schedule.firstLearnedAt
        item.dueAt = schedule.dueAt
        item.intervalSeconds = schedule.intervalSeconds
        item.reviewCount = schedule.reviewCount
        item.lapseCount = schedule.lapseCount
        item.correctStreak = schedule.correctStreak
        item.lastReviewedAt = now
        item.lastRating = rating
        item.updatedAt = now

        let progress = VocabularyProgressCalculator.unitProgress(
            items: unitItems.map(\.learningSnapshot),
            now: now
        )
        let unitWasCompleted = unit.completedAt != nil
        if progress.isComplete {
            unit.completedAt = unit.completedAt ?? now
        } else {
            unit.completedAt = nil
        }

        let activeUnits = units.filter { $0.coursewareID == courseware.id && $0.isActive }
        let coursewareWasCompleted = courseware.completedAt != nil
        if !activeUnits.isEmpty && activeUnits.allSatisfy({ $0.completedAt != nil }) {
            courseware.completedAt = courseware.completedAt ?? now
        } else {
            courseware.completedAt = nil
        }

        context.insert(VocabularyReviewEventRecord(
            itemID: item.id,
            unitID: unit.id,
            coursewareID: courseware.id,
            rating: rating,
            reviewedAt: now,
            previousIntervalSeconds: snapshot.intervalSeconds,
            nextIntervalSeconds: schedule.intervalSeconds
        ))
        do { try context.save() } catch { context.rollback(); throw error }

        return VocabularyReviewOutcome(
            item: item,
            schedule: schedule,
            unitProgress: progress,
            unitDidComplete: !unitWasCompleted && unit.completedAt != nil,
            coursewareDidComplete: !coursewareWasCompleted && courseware.completedAt != nil
        )
    }
}

struct VocabularyReviewOutcome {
    let item: VocabularyItemRecord
    let schedule: VocabularyScheduleResult
    let unitProgress: VocabularyUnitProgress
    let unitDidComplete: Bool
    let coursewareDidComplete: Bool
}

enum VocabularyReviewError: LocalizedError {
    case missingUnit
    case missingCourseware

    var errorDescription: String? {
        switch self {
        case .missingUnit: "The unit containing this entry was not found."
        case .missingCourseware: "The collection containing this entry was not found."
        }
    }
}

private extension VocabularyItemRecord {
    var learningSnapshot: VocabularyLearningSnapshot {
        VocabularyLearningSnapshot(
            firstLearnedAt: firstLearnedAt,
            dueAt: dueAt,
            intervalSeconds: intervalSeconds,
            reviewCount: reviewCount,
            lapseCount: lapseCount,
            correctStreak: correctStreak
        )
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var trimmedNil: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

private extension Optional where Wrapped == String {
    var trimmedNil: String? {
        self?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
