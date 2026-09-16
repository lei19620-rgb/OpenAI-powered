import SwiftData
import UIKit

enum AppPreviewSupport {
    static var isUnitTesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        false
        #endif
    }

    static var isPreview: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-SimpleStudyDemo")
        #else
        false
        #endif
    }

    @MainActor
    static func prepare(context: ModelContext, router: AppRouter) {
        #if DEBUG && targetEnvironment(simulator)
        guard isPreview, ((try? context.fetchCount(FetchDescriptor<CourseRecord>())) ?? 0) == 0 else { return }
        let course = CourseRecord(title: "Reading and Writing")
        let secondCourse = CourseRecord(title: "Design Basics")
        context.insert(course)
        context.insert(secondCourse)
        let workspace = StudyWorkspaceRecord(courseID: course.id, sequence: 1, title: "Day 01 · Reading and Writing")
        context.insert(workspace)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 840))
        let data = renderer.pdfData { renderer in
            renderer.beginPage()
            func draw(_ text: String, y: CGFloat, font: UIFont, color: UIColor = .label) {
                (text as NSString).draw(in: CGRect(x: 48, y: y, width: 504, height: 240),
                    withAttributes: [.font: font, .foregroundColor: color])
            }
            draw("DAY 01   /   READING & EXPRESSION", y: 50, font: .systemFont(ofSize: 13, weight: .semibold), color: .systemBlue)
            draw("Learning starts\nwith curiosity.", y: 100, font: .systemFont(ofSize: 38, weight: .bold))
            draw("Learning begins with curiosity", y: 218, font: .systemFont(ofSize: 20, weight: .medium))
            draw("01  Read and understand", y: 310, font: .systemFont(ofSize: 22, weight: .semibold))
            draw("Every small step makes a difference.\nTake your time, notice the details, and keep learning.", y: 365, font: .systemFont(ofSize: 19))
            draw("02  Note and express", y: 500, font: .systemFont(ofSize: 22, weight: .semibold))
            draw("Record useful words and your own ideas.\nWrite a paragraph using what you learned today.", y: 550, font: .systemFont(ofSize: 18))
        }
        context.insert(StudyAssetRecord(workspaceID: workspace.id, displayName: "Day 01 Reading Guide", originalFileName: "Day 01.pdf", fileData: data))
        let note = StudyNoteRecord(workspaceID: workspace.id, title: "Day 01 · Study Notes", content: "# 📝 Day 01\n\n> **📚 Sentence**\n\nEvery small step makes a difference.\n\n> **📔 Words and Expressions**\n\n- curiosity · a desire to learn\n- make a difference · have an effect\n\n> **📝 Grammar**\n\nSubject + verb + object\n\n> **✅ Output**\n\nRetell the idea in your own words.", template: nil)
        context.insert(note)
        workspace.mainNoteID = note.id
        let prepare = TodoRecord(title: "Prepare materials", kind: .preparation, triggerKind: .manual)
        prepare.storedState = .completed
        prepare.completedAt = Date().addingTimeInterval(-3600)
        context.insert(prepare)
        let reading = TodoRecord(title: "Read lesson one", details: "Reading and Writing · Day 01", kind: .study,
                                 scheduledAt: Date().addingTimeInterval(-1800))
        reading.courseID = course.id
        reading.workspaceID = workspace.id
        reading.completionRule = .lessonCompletion
        reading.prerequisiteIDs = [prepare.id]
        context.insert(reading)
        let journal = TodoRecord(title: "Write a reflection", triggerKind: .manual)
        context.insert(journal)
        let homework = TodoRecord(title: "Complete practice", kind: .homework, triggerKind: .dependencyCompletion)
        homework.prerequisiteIDs = [reading.id]
        context.insert(homework)
        let future = TodoRecord(title: "Evening review", scheduledAt: Date().addingTimeInterval(7200))
        context.insert(future)
        let book = HomeworkDefinitionRecord(package: HomeworkExampleService.package, sourceFileName: "example.sshomework", workspaceID: workspace.id)
        context.insert(book)
        do {
            _ = try VocabularyCoursewareService.importPackage(VocabularyCoursewareService.examplePackage, sourceFileName: "example.json", context: context)
            for item in try context.fetch(FetchDescriptor<VocabularyItemRecord>()).prefix(1) {
                _ = try VocabularyReviewService.record(rating: .known, for: item, context: context,
                                                       now: Date().addingTimeInterval(-86_400))
                item.dueAt = Date().addingTimeInterval(-600)
            }
            try context.save()
        } catch { assertionFailure("Preview data failed: \(error)") }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-SimpleStudyPreviewWorkspace") { router.openStudy(workspaceID: workspace.id) }
        if args.contains("-SimpleStudyPreviewHomework") { router.openHomework(homeworkID: book.id) }
        #endif
    }
}
