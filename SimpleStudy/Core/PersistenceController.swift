import Foundation
import SwiftData

enum PersistenceMode: Equatable {
    case iCloud
    case localOnly
    case localFallback(String)

    var title: String {
        switch self {
        case .iCloud: "iCloud enabled"
        case .localOnly: "On this device"
        case .localFallback: "On this device"
        }
    }

    var details: String {
        switch self {
        case .iCloud: "This session uses your private iCloud database."
        case .localOnly: "iCloud sync is turned off on this device."
        case .localFallback(let reason): "iCloud is unavailable. Using local storage: \(reason)"
        }
    }

    var usesICloud: Bool {
        if case .iCloud = self { return true }
        return false
    }
}

@MainActor
final class PersistenceController: ObservableObject {
    let container: ModelContainer
    @Published private(set) var mode: PersistenceMode
    @Published private(set) var startupIssue: String?

    let iCloudEnabledAtLaunch: Bool

    init(inMemory: Bool = false, iCloudEnabled: Bool = AppSettings.defaultICloudEnabled) {
        iCloudEnabledAtLaunch = iCloudEnabled
        startupIssue = nil
        let schema = Schema([
            AIStudyRecord.self,
            TodoRecord.self,
            CourseRecord.self,
            StudyWorkspaceRecord.self,
            StudyAssetRecord.self,
            NoteTemplateRecord.self,
            StudyNoteRecord.self,
            PDFAnnotationRecord.self,
            HomeworkDefinitionRecord.self,
            HomeworkAttemptRecord.self,
            AlarmRegistrationRecord.self,
            TodoReminderRecord.self,
            TodoNotificationRecord.self,
            VocabularyCoursewareRecord.self,
            VocabularyUnitRecord.self,
            VocabularyItemRecord.self,
            VocabularyReviewEventRecord.self
        ])

        if inMemory {
            let configuration = ModelConfiguration(
                "SimpleStudyPreview",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            container = try! ModelContainer(for: schema, configurations: [configuration])
            mode = .localFallback("Preview database")
            return
        }

        guard iCloudEnabled else {
            do {
                let localConfiguration = ModelConfiguration(
                    "SimpleStudy",
                    schema: schema,
                    cloudKitDatabase: .none
                )
                container = try ModelContainer(for: schema, configurations: [localConfiguration])
                mode = .localOnly
            } catch {
                container = Self.recoveryContainer(for: schema)
                mode = .localFallback("Local storage could not be opened. Recovery session only.")
                startupIssue = "Could not open local storage: \(error.localizedDescription)"
            }
            return
        }

        do {
            let cloudConfiguration = ModelConfiguration(
                "SimpleStudy",
                schema: schema,
                cloudKitDatabase: .automatic
            )
            container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            mode = .iCloud
        } catch {
            do {
                let localConfiguration = ModelConfiguration(
                    "SimpleStudy",
                    schema: schema,
                    cloudKitDatabase: .none
                )
                container = try ModelContainer(for: schema, configurations: [localConfiguration])
                mode = .localFallback(error.localizedDescription)
            } catch {
                container = Self.recoveryContainer(for: schema)
                mode = .localFallback("Neither iCloud nor local storage could be opened. Recovery session only.")
                startupIssue = "Could not open iCloud or local storage: \(error.localizedDescription)"
            }
        }
    }

    private static func recoveryContainer(for schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(
            "SimpleStudyRecovery",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A schema failure is a programming error rather than a recoverable
            // store issue. Keep the diagnostic explicit for development builds.
            fatalError("Could not create the recovery database: \(error.localizedDescription)")
        }
    }
}

@MainActor
enum StarterDataService {
    static func bootstrapIfNeeded(in context: ModelContext) {
        let starters: [(String, String, [NoteBlock])] = [
            (
                "Sentence study",
                "Daily Markdown notes for sentences, vocabulary, grammar, and output",
                [
                    NoteBlock(kind: .heading, title: "📝Day {{day}}   📆{{date}}"),
                    NoteBlock(kind: .quote, title: "• 📚Sentence"),
                    NoteBlock(kind: .quote, title: "• 📔Words and Expressions"),
                    NoteBlock(kind: .quote, title: "• 📝Grammar"),
                    NoteBlock(kind: .quote, title: "• ✅Output")
                ]
            ),
            (
                "PDF study",
                "For handouts and reading materials",
                [
                    NoteBlock(kind: .heading, title: "📄 {{course}} · Day {{day}}"),
                    NoteBlock(kind: .richText, title: "📌 Key ideas"),
                    NoteBlock(kind: .checklist, title: "🔁 Review later", placeholder: "Add topics to revisit"),
                    NoteBlock(kind: .reviewQuestion, title: "💭 Check your understanding", placeholder: "Explain the idea in your own words.")
                ]
            ),
            (
                "Vocabulary review",
                "Record words, context, and your own examples",
                [
                    NoteBlock(kind: .heading, title: "📖 Vocabulary review · Day {{day}}"),
                    NoteBlock(kind: .richText, title: "🆕 New Words"),
                    NoteBlock(kind: .richText, title: "🧠 Meaning & Context"),
                    NoteBlock(kind: .richText, title: "✍️ My Sentences"),
                    NoteBlock(kind: .checklist, title: "🔁 Review", placeholder: "Mark words to revisit today")
                ]
            ),
            (
                "Practice review",
                "Record mistakes and next review steps",
                [
                    NoteBlock(kind: .heading, title: "🧩 Practice review · Day {{day}}"),
                    NoteBlock(kind: .richText, title: "🔍 What went wrong"),
                    NoteBlock(kind: .richText, title: "💡 Key concepts"),
                    NoteBlock(kind: .checklist, title: "🎯 Next review", placeholder: "Write one practical next step")
                ]
            ),
            (
                "Blank",
                "Start with a simple Markdown outline",
                [
                    NoteBlock(kind: .heading, title: "📝 {{course}} · Day {{day}}"),
                    NoteBlock(kind: .richText, title: "✍️ Notes")
                ]
            )
        ]

        let existingTemplates = (try? context.fetch(FetchDescriptor<NoteTemplateRecord>())) ?? []
        for starter in starters {
            if let existing = existingTemplates.first(where: { $0.isStarter && $0.name == starter.0 }) {
                guard existing.version == 1,
                      existing.details != starter.1 || existing.blocks != starter.2 else { continue }
                existing.details = starter.1
                existing.blocks = starter.2
                existing.version += 1
                existing.updatedAt = Date()
            } else {
                context.insert(NoteTemplateRecord(
                    name: starter.0,
                    details: starter.1,
                    blocks: starter.2,
                    isStarter: true
                ))
            }
        }
        try? context.save()
    }
}
