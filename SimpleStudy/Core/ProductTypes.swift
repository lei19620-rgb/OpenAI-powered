import Foundation
import UniformTypeIdentifiers

enum RootTab: Hashable {
    case today
    case study
    case vocabulary
    case my
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum TodoKind: String, Codable, CaseIterable, Identifiable {
    case general
    case preparation
    case study
    case vocabulary
    case homework

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .preparation: "Organize materials"
        case .study: "Study session"
        case .vocabulary: "Memory practice"
        case .homework: "Practice"
        }
    }

    var icon: String {
        switch self {
        case .general: "checkmark.circle"
        case .preparation: "tray.full"
        case .study: "book.pages"
        case .vocabulary: "brain.head.profile"
        case .homework: "checklist.checked"
        }
    }
}

enum TodoTriggerKind: String, Codable, CaseIterable, Identifiable {
    case scheduledTime
    case dependencyCompletion
    case manual
    case courseProgress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduledTime: "At a scheduled time"
        case .dependencyCompletion: "After another task"
        case .manual: "Start anytime"
        case .courseProgress: "When progress changes"
        }
    }

    static let creationOptions: [TodoTriggerKind] = [.manual, .scheduledTime, .dependencyCompletion]
}

enum RecurrencePolicy: String, Codable, CaseIterable, Identifiable {
    case none
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Never"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

enum MissedOccurrencePolicy: String, Codable, CaseIterable, Identifiable {
    case carryForward
    case accumulate

    var id: String { rawValue }
    var title: String { self == .carryForward ? "Carry forward the current task" : "Keep every missed occurrence" }
}

enum TodoState: String, Codable {
    case scheduled
    case waitingDependency
    case ready
    case overdue
    case runningActions
    case partialFailure
    case completed
    case cancelled

    var title: String {
        switch self {
        case .scheduled: "Scheduled"
        case .waitingDependency: "Waiting for prerequisites"
        case .ready: "Ready"
        case .overdue: "Overdue"
        case .runningActions: "Running actions"
        case .partialFailure: "Some actions failed"
        case .completed: "Completed"
        case .cancelled: "Canceled"
        }
    }
}

enum TodoCompletionRule: String, Codable, CaseIterable, Identifiable {
    case manual
    case homeworkSubmission
    case lessonCompletion
    case vocabularyUnitCompletion
    case vocabularyCoursewareCompletion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "Mark complete manually"
        case .homeworkSubmission: "After submitting practice"
        case .lessonCompletion: "After finishing the lesson"
        case .vocabularyUnitCompletion: "After studying the word group"
        case .vocabularyCoursewareCompletion: "After studying the word collection"
        }
    }
}

enum TodoActionKind: String, Codable, CaseIterable, Identifiable {
    case scheduleAlarm
    case localNotification
    case createWorkspace
    case createNote
    case resolveCourseMaterial
    case openStudy
    case openHomework
    case openVocabularyReview
    case vocabularyReminder
    case updateCourseProgress
    case runShortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduleAlarm: "Set an alarm"
        case .localNotification: "Send a notification"
        case .createWorkspace: "Create a workspace"
        case .createNote: "Create a note from a template"
        case .resolveCourseMaterial: "Link study materials"
        case .openStudy: "Open workspace"
        case .openHomework: "Open practice"
        case .openVocabularyReview: "Open vocabulary review"
        case .vocabularyReminder: "Send a review reminder"
        case .updateCourseProgress: "Advance course progress"
        case .runShortcut: "Run a shortcut"
        }
    }

    var icon: String {
        switch self {
        case .scheduleAlarm: "alarm"
        case .localNotification: "bell"
        case .createWorkspace: "rectangle.3.group"
        case .createNote: "note.text.badge.plus"
        case .resolveCourseMaterial: "doc.badge.gearshape"
        case .openStudy: "book.pages"
        case .openHomework: "pencil.and.list.clipboard"
        case .openVocabularyReview: "character.book.closed"
        case .vocabularyReminder: "brain.head.profile"
        case .updateCourseProgress: "arrow.forward.circle"
        case .runShortcut: "square.stack.3d.up"
        }
    }

    static let creationOptions: [TodoActionKind] = [
        .scheduleAlarm,
        .localNotification,
        .createWorkspace,
        .createNote,
        .resolveCourseMaterial,
        .openStudy,
        .openHomework,
        .openVocabularyReview,
        .updateCourseProgress,
        .runShortcut
    ]
}

enum TodoActionPhase: String, Codable, CaseIterable, Identifiable {
    case activation
    case completion

    var id: String { rawValue }
    var title: String { self == .activation ? "When the task starts" : "When the task is completed" }
}

enum TodoActionState: String, Codable {
    case pending
    case running
    case succeeded
    case failed
    case skipped
}

enum AlarmTarget: String, Codable, CaseIterable, Identifiable {
    case iPhone
    case currentIPad
    case allAuthorizedDevices
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iPhone: "iPhone (default)"
        case .currentIPad: "This iPad"
        case .allAuthorizedDevices: "All authorized devices"
        case .none: "No alarm"
        }
    }
}

enum AlarmRegistrationState: String, Codable {
    case notRequested
    case awaitingDevice
    case scheduled
    case fired
    case stopped
    case failed
    case permissionDenied

    var title: String {
        switch self {
        case .notRequested: "Not set"
        case .awaitingDevice: "Waiting for the target device"
        case .scheduled: "Scheduled"
        case .fired: "Rang"
        case .stopped: "Stopped"
        case .failed: "Setup failed"
        case .permissionDenied: "Alarm access denied"
        }
    }
}

enum TodoReminderState: String, Codable {
    case pending
    case active
    case completed
    case deleted
    case failed

    var title: String {
        switch self {
        case .pending: "Pending sync"
        case .active: "Synced"
        case .completed: "Completed"
        case .deleted: "Deleted"
        case .failed: "Sync failed"
        }
    }
}

enum TodoNotificationState: String, Codable {
    case pending
    case scheduled
    case failed

    var title: String {
        switch self {
        case .pending: "Awaiting notification access"
        case .scheduled: "Scheduled"
        case .failed: "Scheduling failed"
        }
    }
}

struct TodoActionParameters: Codable, Equatable {
    var alarmTarget: AlarmTarget = .none
    var alarmTargetDeviceID: String? = nil
    var reminderOffsetMinutes: Int = 0
    var reminderRepeatMinutes: Int = 0
    var courseID: UUID? = nil
    var workspaceID: UUID? = nil
    var noteTemplateID: UUID? = nil
    var homeworkID: UUID? = nil
    var vocabularyCoursewareID: UUID? = nil
    var vocabularyUnitID: UUID? = nil
    var message: String = ""
    var shortcutName: String = ""
}

enum ActionNavigationRequest: Equatable {
    case study(UUID?)
    case homework(UUID?)
    case vocabulary(coursewareID: UUID?, unitID: UUID?)
}

struct TodoAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: TodoActionKind
    var phase: TodoActionPhase
    var isEnabled: Bool = true
    var isCritical: Bool = true
    var parameters: TodoActionParameters = .init()
    var state: TodoActionState = .pending
    var idempotencyKey: String = UUID().uuidString
    var attemptCount: Int = 0
    var startedAt: Date?
    var finishedAt: Date?
    var errorMessage: String?
}

enum TodoQuickPlan: String, CaseIterable, Identifiable {
    case basic
    case reminder
    case alarm
    case openContent
    case chained
    case recurring
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: "Simple task"
        case .reminder: "Scheduled reminder"
        case .alarm: "Alarm"
        case .openContent: "Open linked content"
        case .chained: "Task sequence"
        case .recurring: "Repeating task"
        case .custom: "Custom workflow"
        }
    }

    var subtitle: String {
        switch self {
        case .basic: "Start anytime and mark complete"
        case .reminder: "Send a notification at the scheduled time"
        case .alarm: "Ring on the selected device"
        case .openContent: "Open linked content when starting"
        case .chained: "Start after the previous task is complete"
        case .recurring: "Repeat on schedule and carry forward"
        case .custom: "Build a workflow from scratch"
        }
    }

    var icon: String {
        switch self {
        case .basic: "checkmark.circle"
        case .reminder: "bell"
        case .alarm: "alarm"
        case .openContent: "rectangle.and.text.magnifyingglass"
        case .chained: "link"
        case .recurring: "repeat"
        case .custom: "slider.horizontal.3"
        }
    }
}

enum NoteBlockKind: String, Codable, CaseIterable, Identifiable {
    case heading
    case richText
    case checklist
    case quote
    case table
    case attachment
    case divider
    case handwriting
    case reviewQuestion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heading: "Title"
        case .richText: "Body"
        case .checklist: "Checklist"
        case .quote: "Quote"
        case .table: "Table"
        case .attachment: "Attachment slot"
        case .divider: "Divider"
        case .handwriting: "Handwriting"
        case .reviewQuestion: "Review question"
        }
    }

    var suggestedTitle: String {
        switch self {
        case .heading: "📌 Title"
        case .richText: "✍️ Body"
        case .checklist: "✅ Checklist"
        case .quote: "💬 Quote"
        case .table: "📊 Table"
        case .attachment: "📎 Attachment"
        case .divider: "➖ Divider"
        case .handwriting: "✏️ Handwriting"
        case .reviewQuestion: "🤔 Review question"
        }
    }
}

struct NoteBlock: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: NoteBlockKind
    var title: String
    var placeholder: String = ""
}

struct NoteTemplateSnapshot: Codable, Equatable {
    var templateID: UUID
    var version: Int
    var name: String
    var blocks: [NoteBlock]
}

struct LessonSequenceInference: Codable, Equatable {
    var sequence: Int
    var confidence: Double
    var evidence: String
}

enum HomeworkQuestionType: String, Codable, CaseIterable {
    case singleChoice
    case multipleChoice
    case fillBlank
    case openResponse

    var title: String {
        switch self {
        case .singleChoice: "Single choice"
        case .multipleChoice: "Multiple choice"
        case .fillBlank: "Fill in the blank"
        case .openResponse: "Open response"
        }
    }
}

struct HomeworkOption: Codable, Identifiable, Equatable {
    let id: String
    let text: String
}

struct HomeworkCorrectAnswer: Codable, Equatable {
    var selectedOptionIDs: [String]? = nil
    var acceptedTexts: [String]? = nil
    var referenceText: String? = nil
}

struct HomeworkQuestion: Codable, Identifiable, Equatable {
    let id: String
    let type: HomeworkQuestionType
    let prompt: String
    var options: [HomeworkOption]? = nil
    let answer: HomeworkCorrectAnswer
    let explanation: String
    let points: Double
    let required: Bool
}

struct HomeworkPackage: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let title: String
    var courseID: String? = nil
    var lessonSequence: Int? = nil
    let questions: [HomeworkQuestion]
}

struct HomeworkResponse: Codable, Equatable {
    var selectedOptionIDs: [String] = []
    var text: String = ""

    var isEmpty: Bool { selectedOptionIDs.isEmpty && text.isEmpty }
}

enum HomeworkQuestionOutcome: String, Codable {
    case correct
    case incorrect
    case awaitingSelfReview
    case unanswered
}

struct HomeworkQuestionResult: Codable, Identifiable, Equatable {
    var id: String { questionID }
    let questionID: String
    let outcome: HomeworkQuestionOutcome
    let earnedPoints: Double
}

struct HomeworkGradeSummary: Codable, Equatable {
    let totalQuestions: Int
    let answeredQuestions: Int
    let correctObjectiveQuestions: Int
    let incorrectObjectiveQuestions: Int
    let objectiveQuestions: Int
    let earnedPoints: Double
    let possiblePoints: Double
    let results: [HomeworkQuestionResult]

    var objectiveAccuracy: Double {
        guard objectiveQuestions > 0 else { return 0 }
        return Double(correctObjectiveQuestions) / Double(objectiveQuestions)
    }
}

enum HomeworkAttemptState: String, Codable {
    case draft
    case submitted
}

enum ProductFileType {
    static let homework = UTType(importedAs: "app.studyai.homework", conformingTo: .json)
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, default fallback: T) -> T {
        guard !data.isEmpty else { return fallback }
        return (try? decoder.decode(type, from: data)) ?? fallback
    }
}
