import Foundation
import SwiftData

@Model
final class TodoRecord {
    var id: UUID = UUID()
    var seriesID: UUID = UUID()
    var occurrenceIndex: Int = 0
    var title: String = ""
    var details: String = ""
    var kindRaw: String = TodoKind.general.rawValue
    var triggerKindRaw: String = TodoTriggerKind.scheduledTime.rawValue
    var recurrenceRaw: String = RecurrencePolicy.none.rawValue
    var missedPolicyRaw: String = MissedOccurrencePolicy.carryForward.rawValue
    var completionRuleRaw: String = TodoCompletionRule.manual.rawValue
    var storedStateRaw: String = TodoState.scheduled.rawValue
    var originalScheduledAt: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?
    var courseID: UUID?
    var workspaceID: UUID?
    var homeworkID: UUID?
    var vocabularyCoursewareID: UUID?
    var vocabularyUnitID: UUID?
    var prerequisiteIDsData: Data = Data()
    var actionsData: Data = Data()
    var alarmStateRaw: String = AlarmRegistrationState.notRequested.rawValue
    var lastActionError: String?
    // Durable evidence for a completed vocabulary session, separate from task readiness.
    var learningEvidenceAt: Date?

    init(
        title: String,
        details: String = "",
        kind: TodoKind = .general,
        triggerKind: TodoTriggerKind = .scheduledTime,
        scheduledAt: Date = Date()
    ) {
        self.id = UUID()
        self.seriesID = self.id
        self.title = title
        self.details = details
        self.kindRaw = kind.rawValue
        self.triggerKindRaw = triggerKind.rawValue
        self.originalScheduledAt = scheduledAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kind: TodoKind {
        get { TodoKind(rawValue: kindRaw) ?? .general }
        set { kindRaw = newValue.rawValue }
    }

    var triggerKind: TodoTriggerKind {
        get { TodoTriggerKind(rawValue: triggerKindRaw) ?? .scheduledTime }
        set { triggerKindRaw = newValue.rawValue }
    }

    var recurrence: RecurrencePolicy {
        get { RecurrencePolicy(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    var missedPolicy: MissedOccurrencePolicy {
        get { MissedOccurrencePolicy(rawValue: missedPolicyRaw) ?? .carryForward }
        set { missedPolicyRaw = newValue.rawValue }
    }

    var completionRule: TodoCompletionRule {
        get { TodoCompletionRule(rawValue: completionRuleRaw) ?? .manual }
        set { completionRuleRaw = newValue.rawValue }
    }

    var storedState: TodoState {
        get { TodoState(rawValue: storedStateRaw) ?? .scheduled }
        set { storedStateRaw = newValue.rawValue }
    }

    var alarmState: AlarmRegistrationState {
        get { AlarmRegistrationState(rawValue: alarmStateRaw) ?? .notRequested }
        set { alarmStateRaw = newValue.rawValue }
    }

    var prerequisiteIDs: [UUID] {
        get { JSONCoding.decode([UUID].self, from: prerequisiteIDsData, default: []) }
        set { prerequisiteIDsData = JSONCoding.encode(newValue) }
    }

    var actions: [TodoAction] {
        get { JSONCoding.decode([TodoAction].self, from: actionsData, default: []) }
        set { actionsData = JSONCoding.encode(newValue) }
    }
}

@Model
final class CourseRecord {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var currentSequence: Int = 1
    var missedPolicyRaw: String = MissedOccurrencePolicy.carryForward.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(title: String, details: String = "") {
        self.id = UUID()
        self.title = title
        self.details = details
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var missedPolicy: MissedOccurrencePolicy {
        get { MissedOccurrencePolicy(rawValue: missedPolicyRaw) ?? .carryForward }
        set { missedPolicyRaw = newValue.rawValue }
    }
}

@Model
final class StudyWorkspaceRecord {
    var id: UUID = UUID()
    var courseID: UUID = UUID()
    var sequence: Int = 1
    var title: String = ""
    var mainNoteID: UUID?
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date?

    init(courseID: UUID, sequence: Int, title: String) {
        self.id = UUID()
        self.courseID = courseID
        self.sequence = sequence
        self.title = title
        self.createdAt = Date()
    }
}

@Model
final class StudyAssetRecord {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var displayName: String = ""
    var originalFileName: String = ""
    var contentType: String = "application/pdf"
    @Attribute(.externalStorage) var fileData: Data = Data()
    var resolvedSequence: Int = 1
    var inferenceConfidence: Double = 0
    var inferenceEvidence: String = ""
    var ocrText: String = ""
    var extractedQuestionsData: Data = Data()
    var importedAt: Date = Date()

    init(workspaceID: UUID, displayName: String, originalFileName: String, fileData: Data) {
        self.id = UUID()
        self.workspaceID = workspaceID
        self.displayName = displayName
        self.originalFileName = originalFileName
        self.fileData = fileData
        self.importedAt = Date()
    }

    var extractedQuestions: [String] {
        get { JSONCoding.decode([String].self, from: extractedQuestionsData, default: []) }
        set { extractedQuestionsData = JSONCoding.encode(newValue) }
    }
}

@Model
final class NoteTemplateRecord {
    var id: UUID = UUID()
    var name: String = ""
    var details: String = ""
    var version: Int = 1
    var isStarter: Bool = false
    var blocksData: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, details: String = "", blocks: [NoteBlock], isStarter: Bool = false) {
        self.id = UUID()
        self.name = name
        self.details = details
        self.isStarter = isStarter
        self.blocksData = JSONCoding.encode(blocks)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var blocks: [NoteBlock] {
        get { JSONCoding.decode([NoteBlock].self, from: blocksData, default: []) }
        set { blocksData = JSONCoding.encode(newValue) }
    }

    var snapshot: NoteTemplateSnapshot {
        NoteTemplateSnapshot(templateID: id, version: version, name: name, blocks: blocks)
    }
}

@Model
final class StudyNoteRecord {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var templateID: UUID?
    var templateVersion: Int = 0
    var templateSnapshotData: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(workspaceID: UUID, title: String, content: String, template: NoteTemplateSnapshot?) {
        self.id = UUID()
        self.workspaceID = workspaceID
        self.title = title
        self.content = content
        self.templateID = template?.templateID
        self.templateVersion = template?.version ?? 0
        self.templateSnapshotData = template.map(JSONCoding.encode) ?? Data()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class PDFAnnotationRecord {
    var id: UUID = UUID()
    var assetID: UUID = UUID()
    var pageIndex: Int = 0
    @Attribute(.externalStorage) var drawingData: Data = Data()
    var updatedAt: Date = Date()

    init(assetID: UUID, pageIndex: Int, drawingData: Data = Data()) {
        self.id = UUID()
        self.assetID = assetID
        self.pageIndex = pageIndex
        self.drawingData = drawingData
        self.updatedAt = Date()
    }
}

@Model
final class HomeworkDefinitionRecord {
    var id: UUID = UUID()
    var packageID: String = ""
    var workspaceID: UUID?
    var title: String = ""
    var sourceFileName: String = ""
    @Attribute(.externalStorage) var packageData: Data = Data()
    var importedAt: Date = Date()

    init(package: HomeworkPackage, sourceFileName: String, workspaceID: UUID? = nil) {
        self.id = UUID()
        self.packageID = package.id
        self.workspaceID = workspaceID
        self.title = package.title
        self.sourceFileName = sourceFileName
        self.packageData = JSONCoding.encode(package)
        self.importedAt = Date()
    }

    var package: HomeworkPackage? {
        try? JSONCoding.decoder.decode(HomeworkPackage.self, from: packageData)
    }
}

@Model
final class HomeworkAttemptRecord {
    var id: UUID = UUID()
    var homeworkID: UUID = UUID()
    var attemptNumber: Int = 1
    var stateRaw: String = HomeworkAttemptState.draft.rawValue
    var answersData: Data = Data()
    var gradeData: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var submittedAt: Date?

    init(homeworkID: UUID, attemptNumber: Int) {
        self.id = UUID()
        self.homeworkID = homeworkID
        self.attemptNumber = attemptNumber
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var state: HomeworkAttemptState {
        get { HomeworkAttemptState(rawValue: stateRaw) ?? .draft }
        set { stateRaw = newValue.rawValue }
    }

    var answers: [String: HomeworkResponse] {
        get { JSONCoding.decode([String: HomeworkResponse].self, from: answersData, default: [:]) }
        set { answersData = JSONCoding.encode(newValue) }
    }

    var grade: HomeworkGradeSummary? {
        guard !gradeData.isEmpty else { return nil }
        return try? JSONCoding.decoder.decode(HomeworkGradeSummary.self, from: gradeData)
    }
}

@Model
final class AlarmRegistrationRecord {
    var id: UUID = UUID()
    var todoID: UUID = UUID()
    var deviceID: String = ""
    var deviceKind: String = ""
    var alarmID: UUID?
    var stateRaw: String = AlarmRegistrationState.notRequested.rawValue
    var requestedFireDate: Date = Date()
    var updatedAt: Date = Date()
    var errorMessage: String?

    init(todoID: UUID, deviceID: String, deviceKind: String, fireDate: Date) {
        self.id = UUID()
        self.todoID = todoID
        self.deviceID = deviceID
        self.deviceKind = deviceKind
        self.requestedFireDate = fireDate
        self.updatedAt = Date()
    }

    var state: AlarmRegistrationState {
        get { AlarmRegistrationState(rawValue: stateRaw) ?? .notRequested }
        set { stateRaw = newValue.rawValue }
    }
}

@Model
final class TodoReminderRecord {
    var id: UUID = UUID()
    var todoID: UUID = UUID()
    var actionID: UUID?
    var stepKey: String = "task"
    var deviceID: String = ""
    var deviceKind: String = ""
    var reminderIdentifier: String?
    var title: String = ""
    var dueDate: Date = Date()
    var stateRaw: String = TodoReminderState.pending.rawValue
    var updatedAt: Date = Date()
    var errorMessage: String?

    init(
        todoID: UUID,
        actionID: UUID?,
        stepKey: String,
        deviceID: String,
        deviceKind: String,
        title: String,
        dueDate: Date
    ) {
        self.id = UUID()
        self.todoID = todoID
        self.actionID = actionID
        self.stepKey = stepKey
        self.deviceID = deviceID
        self.deviceKind = deviceKind
        self.title = title
        self.dueDate = dueDate
        self.updatedAt = Date()
    }

    var state: TodoReminderState {
        get { TodoReminderState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }
}

@Model
final class TodoNotificationRecord {
    var id: UUID = UUID()
    var todoID: UUID = UUID()
    var actionID: UUID?
    var stepKey: String = "task"
    var deviceID: String = ""
    var deviceKind: String = ""
    var notificationIdentifier: String = ""
    var title: String = ""
    var body: String = ""
    var dueDate: Date = Date()
    var stateRaw: String = TodoNotificationState.pending.rawValue
    var updatedAt: Date = Date()
    var errorMessage: String?

    init(
        todoID: UUID,
        actionID: UUID?,
        stepKey: String,
        deviceID: String,
        deviceKind: String,
        notificationIdentifier: String,
        title: String,
        body: String,
        dueDate: Date
    ) {
        self.id = UUID()
        self.todoID = todoID
        self.actionID = actionID
        self.stepKey = stepKey
        self.deviceID = deviceID
        self.deviceKind = deviceKind
        self.notificationIdentifier = notificationIdentifier
        self.title = title
        self.body = body
        self.dueDate = dueDate
        self.updatedAt = Date()
    }

    var state: TodoNotificationState {
        get { TodoNotificationState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }
}
