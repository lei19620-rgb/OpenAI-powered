import Foundation
import SwiftData

/// A vocabulary courseware file is a user-owned learning source. It is intentionally
/// separate from the local dictionary package: courseware contains the words to learn,
/// while a dictionary package contains lookup data.
@Model
final class VocabularyCoursewareRecord {
    var id: UUID = UUID()
    var coursewareKey: String = ""
    var title: String = ""
    var curriculumKey: String?
    var sourceFileName: String = ""
    var sourceFormat: String = "json"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?

    init(
        coursewareKey: String,
        title: String,
        curriculumKey: String? = nil,
        sourceFileName: String = "",
        sourceFormat: String = "json"
    ) {
        self.id = UUID()
        self.coursewareKey = coursewareKey
        self.title = title
        self.curriculumKey = curriculumKey
        self.sourceFileName = sourceFileName
        self.sourceFormat = sourceFormat
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class VocabularyUnitRecord {
    var id: UUID = UUID()
    var coursewareID: UUID = UUID()
    var unitKey: String = ""
    var sequence: Int = 1
    var title: String = ""
    var unitType: String = "unit"
    var sourceLabel: String = ""
    var expectedCount: Int?
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?

    init(
        coursewareID: UUID,
        unitKey: String,
        sequence: Int,
        title: String,
        unitType: String = "unit",
        sourceLabel: String = "",
        expectedCount: Int? = nil
    ) {
        self.id = UUID()
        self.coursewareID = coursewareID
        self.unitKey = unitKey
        self.sequence = sequence
        self.title = title
        self.unitType = unitType
        self.sourceLabel = sourceLabel
        self.expectedCount = expectedCount
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class VocabularyItemRecord {
    var id: UUID = UUID()
    var coursewareID: UUID = UUID()
    var unitID: UUID = UUID()
    var sourceItemKey: String = ""
    var order: Int = 0
    var term: String = ""
    var phoneticUK: String = ""
    var phoneticUS: String = ""
    var partOfSpeech: String = ""
    var meaning: String = ""
    var example: String = ""
    var note: String = ""
    var tagsData: Data = Data()
    var isActive: Bool = true

    // Spaced-repetition state. The first rating is enough to finish first learning;
    // later ratings only affect review scheduling and mastery.
    var learningStateRaw: String = VocabularyLearningState.new.rawValue
    var firstLearnedAt: Date?
    var dueAt: Date?
    var intervalSeconds: Double = 0
    var reviewCount: Int = 0
    var lapseCount: Int = 0
    var correctStreak: Int = 0
    var lastReviewedAt: Date?
    var lastRatingRaw: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        coursewareID: UUID,
        unitID: UUID,
        sourceItemKey: String,
        order: Int,
        term: String,
        phoneticUK: String = "",
        phoneticUS: String = "",
        partOfSpeech: String = "",
        meaning: String = "",
        example: String = "",
        note: String = "",
        tags: [String] = []
    ) {
        self.id = UUID()
        self.coursewareID = coursewareID
        self.unitID = unitID
        self.sourceItemKey = sourceItemKey
        self.order = order
        self.term = term
        self.phoneticUK = phoneticUK
        self.phoneticUS = phoneticUS
        self.partOfSpeech = partOfSpeech
        self.meaning = meaning
        self.example = example
        self.note = note
        self.tagsData = JSONCoding.encode(tags)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var tags: [String] {
        get { JSONCoding.decode([String].self, from: tagsData, default: []) }
        set { tagsData = JSONCoding.encode(newValue) }
    }

    var learningState: VocabularyLearningState {
        get { VocabularyLearningState(rawValue: learningStateRaw) ?? .new }
        set { learningStateRaw = newValue.rawValue }
    }

    var lastRating: VocabularyRating? {
        get { lastRatingRaw.flatMap(VocabularyRating.init(rawValue:)) }
        set { lastRatingRaw = newValue?.rawValue }
    }
}

@Model
final class VocabularyReviewEventRecord {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var unitID: UUID = UUID()
    var coursewareID: UUID = UUID()
    var ratingRaw: String = VocabularyRating.fuzzy.rawValue
    var reviewedAt: Date = Date()
    var previousIntervalSeconds: Double = 0
    var nextIntervalSeconds: Double = 0

    init(
        itemID: UUID,
        unitID: UUID,
        coursewareID: UUID,
        rating: VocabularyRating,
        reviewedAt: Date,
        previousIntervalSeconds: Double,
        nextIntervalSeconds: Double
    ) {
        self.id = UUID()
        self.itemID = itemID
        self.unitID = unitID
        self.coursewareID = coursewareID
        self.ratingRaw = rating.rawValue
        self.reviewedAt = reviewedAt
        self.previousIntervalSeconds = previousIntervalSeconds
        self.nextIntervalSeconds = nextIntervalSeconds
    }

    var rating: VocabularyRating {
        get { VocabularyRating(rawValue: ratingRaw) ?? .fuzzy }
        set { ratingRaw = newValue.rawValue }
    }
}
