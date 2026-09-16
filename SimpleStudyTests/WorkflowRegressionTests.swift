import XCTest
import SwiftData
@testable import SimpleStudy

@MainActor
final class WorkflowRegressionTests: XCTestCase {
    func testFailureCannotBypassUnfinishedDependency() async throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let first = TodoRecord(title: "Wake up", triggerKind: .manual)
        let second = TodoRecord(title: "Prepare materials", triggerKind: .dependencyCompletion)
        second.prerequisiteIDs = [first.id]
        second.storedState = .partialFailure
        context.insert(first)
        context.insert(second)
        try context.save()
        XCTAssertEqual(TodoStateResolver.state(for: second, allTodos: [first, second]), .waitingDependency)
        await TodoActionEngine().complete(todo: second, context: context)
        XCTAssertNil(second.completedAt)
    }

    func testRecurringSuccessorWaitsUntilTomorrowAndKeepsClockTime() async throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let calendar = Calendar.current
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: Date()))
        let planned = try XCTUnwrap(calendar.date(bySettingHour: 7, minute: 15, second: 0, of: yesterday))
        let todo = TodoRecord(title: "Daily reading", triggerKind: .scheduledTime, scheduledAt: planned)
        todo.recurrence = .daily
        todo.actions = [TodoAction(kind: .openStudy, phase: .activation, state: .succeeded)]
        context.insert(todo)
        try context.save()
        let engine = TodoActionEngine()
        await engine.complete(todo: todo, context: context)
        let all = try context.fetch(FetchDescriptor<TodoRecord>())
        let next = try XCTUnwrap(all.first { $0.id != todo.id })
        XCTAssertEqual(next.triggerKind, .scheduledTime)
        XCTAssertEqual(next.prerequisiteIDs, [todo.id])
        XCTAssertTrue(calendar.isDateInTomorrow(next.originalScheduledAt))
        XCTAssertEqual(calendar.component(.hour, from: next.originalScheduledAt), 7)
        XCTAssertEqual(calendar.component(.minute, from: next.originalScheduledAt), 15)
        XCTAssertEqual(TodoStateResolver.state(for: next, allTodos: all), .scheduled)
        XCTAssertEqual(next.actions.first?.state, .pending)
        XCTAssertNil(engine.navigationRequest)
        await engine.complete(todo: next, context: context)
        XCTAssertNil(next.completedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TodoRecord>()).count, 2)
    }

    func testRetryRecoversStateWithoutDuplicatingWorkspace() async throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let course = CourseRecord(title: "Reading")
        let todo = TodoRecord(title: "Prepare", triggerKind: .manual)
        todo.actions = [TodoAction(kind: .createWorkspace, phase: .activation, parameters: .init(courseID: course.id))]
        context.insert(todo)
        try context.save()
        let engine = TodoActionEngine()
        await engine.activate(todo: todo, context: context)
        XCTAssertEqual(todo.storedState, .partialFailure)
        context.insert(course)
        try context.save()
        await engine.retryFailedActions(todo: todo, context: context)
        XCTAssertEqual(todo.storedState, .ready)
        XCTAssertNil(todo.lastActionError)
        await engine.retryFailedActions(todo: todo, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudyWorkspaceRecord>()).count, 1)
    }

    func testBackgroundRefreshDoesNotStealNavigation() async throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let todo = TodoRecord(title: "Open reading", scheduledAt: Date().addingTimeInterval(-30))
        todo.actions = [TodoAction(kind: .openStudy, phase: .activation)]
        context.insert(todo)
        try context.save()
        let engine = TodoActionEngine()
        await engine.refreshAndActivateReadyTasks(context: context)
        XCTAssertNil(engine.navigationRequest)
        XCTAssertEqual(todo.actions.first?.state, .succeeded)
    }

    func testCycleDetectionIncludesIndirectDependencies() {
        let a = TodoRecord(title: "A")
        let b = TodoRecord(title: "B")
        let c = TodoRecord(title: "C")
        b.prerequisiteIDs = [a.id]
        c.prerequisiteIDs = [b.id]
        XCTAssertTrue(TodoDependencyValidator.createsCycle(todoID: a.id, prerequisites: [c.id], allTodos: [a, b, c]))
        XCTAssertFalse(TodoDependencyValidator.createsCycle(todoID: c.id, prerequisites: [a.id], allTodos: [a, b, c]))
    }

    func testManualTaskDoesNotDisplayOverdue() {
        let todo = TodoRecord(title: "Read anytime", triggerKind: .manual, scheduledAt: .distantPast)
        XCTAssertNil(TodoStateResolver.overdueText(for: todo))
    }

    func testOptionalActionFailureDoesNotBlockBusinessCompletion() async throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let todo = TodoRecord(title: "Assignment completed", triggerKind: .manual)
        todo.actions = [TodoAction(kind: .createWorkspace, phase: .activation, isCritical: false)]
        context.insert(todo)
        try context.save()
        let engine = TodoActionEngine()
        await engine.activate(todo: todo, context: context)
        XCTAssertEqual(todo.storedState, .partialFailure)
        await engine.complete(todo: todo, context: context)
        XCTAssertEqual(todo.storedState, .completed)
        XCTAssertEqual(todo.actions.first?.state, .failed)
    }

    func testInterruptedActionCanBeRetriedAfterRelaunch() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let todo = TodoRecord(title: "Prepare materials", triggerKind: .manual)
        todo.storedState = .runningActions
        todo.actions = [TodoAction(kind: .createWorkspace, phase: .activation, state: .running)]
        context.insert(todo)
        try context.save()
        TodoActionEngine().refreshStates(context: context)
        XCTAssertEqual(todo.storedState, .partialFailure)
        XCTAssertEqual(todo.actions.first?.state, .failed)
    }

    func testHomeworkRequiresRequiredAnswersAndPreservesSubmittedHistory() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let id = UUID()
        let attempt = try HomeworkAttemptService.currentOrLatest(for: id, context: context)
        let package = HomeworkExampleService.package
        XCTAssertThrowsError(try HomeworkAttemptService.submit(attempt: attempt, package: package, responses: [:], context: context))
        XCTAssertEqual(attempt.state, .draft)
        let answers: [String: HomeworkResponse] = [
            "q1": HomeworkResponse(selectedOptionIDs: ["a"]),
            "q2": HomeworkResponse(selectedOptionIDs: ["a", "b"]),
            "q3": HomeworkResponse(text: "civilization")
        ]
        try HomeworkAttemptService.submit(attempt: attempt, package: package, responses: answers, context: context)
        XCTAssertThrowsError(try HomeworkAttemptService.submit(attempt: attempt, package: package, responses: answers, context: context))
        let completedTodo = TodoRecord(title: "Complete assignment")
        completedTodo.storedState = .completed
        context.insert(completedTodo)
        try context.save()
        let fresh = try HomeworkAttemptService.reset(homeworkID: id, context: context)
        XCTAssertTrue(fresh.answers.isEmpty)
        XCTAssertEqual(fresh.attemptNumber, 2)
        XCTAssertEqual(attempt.state, .submitted)
        XCTAssertEqual(attempt.answers["q3"]?.text, "civilization")
        XCTAssertEqual(completedTodo.storedState, .completed)
    }

    func testReimportRecalculatesProgressAfterRemovingUnlearnedWord() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        func package(_ items: [VocabularyItemPackage]) -> VocabularyCoursewarePackage {
            .init(id: "same-book", title: "Vocabulary", units: [.init(key: "unit-1", sequence: 1, title: "Group One", items: items)])
        }
        let first = VocabularyItemPackage(key: "a", term: "learn", meaning: "Study")
        let removed = VocabularyItemPackage(key: "b", term: "write", meaning: "\u{5199}")
        _ = try VocabularyCoursewareService.importPackage(package([first, removed]), sourceFileName: "book.json", context: context)
        let item = try XCTUnwrap(try context.fetch(FetchDescriptor<VocabularyItemRecord>()).first { $0.sourceItemKey == "a" })
        _ = try VocabularyReviewService.record(rating: .known, for: item, context: context)
        _ = try VocabularyCoursewareService.importPackage(package([first]), sourceFileName: "book.json", context: context)
        let unit = try XCTUnwrap(try context.fetch(FetchDescriptor<VocabularyUnitRecord>()).first)
        XCTAssertNotNil(unit.completedAt)
        XCTAssertEqual(try VocabularyReviewService.items(for: unit.id, context: context).count, 1)
        XCTAssertNotNil(try context.fetch(FetchDescriptor<VocabularyCoursewareRecord>()).first?.completedAt)
        _ = try VocabularyCoursewareService.importPackage(package([first, removed]), sourceFileName: "book.json", context: context)
        XCTAssertNil(unit.completedAt)
        XCTAssertNotNil(item.firstLearnedAt)
    }

    func testReviewValidationDoesNotMutateOrphanedWord() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        _ = try VocabularyCoursewareService.importPackage(VocabularyCoursewareService.examplePackage, sourceFileName: "book.json", context: context)
        let item = try XCTUnwrap(try context.fetch(FetchDescriptor<VocabularyItemRecord>()).first)
        item.unitID = UUID()
        try context.save()
        XCTAssertThrowsError(try VocabularyReviewService.record(rating: .known, for: item, context: context))
        XCTAssertNil(item.firstLearnedAt)
        XCTAssertEqual(item.reviewCount, 0)
    }

    func testMaterialBatchSharesWorkspaceAndSkipsExactDuplicate() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let course = CourseRecord(title: "Course")
        context.insert(course)
        try context.save()
        let a = PreparedStudyMaterial(fileName: "Day 1.pdf", data: Data([1]), sequence: 1, confidence: 0.98, evidence: "filename", questions: [])
        let b = PreparedStudyMaterial(fileName: "Day 1 Supplement.pdf", data: Data([2]), sequence: 1, confidence: 0.98, evidence: "filename", questions: [])
        try StudyMaterialImporter.commit([a, b, a], course: course, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudyWorkspaceRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudyAssetRecord>()).count, 2)
    }

    func testCourseProgressDoesNotSkipUnfinishedLessons() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let course = CourseRecord(title: "Course")
        let first = StudyWorkspaceRecord(courseID: course.id, sequence: 1, title: "Lesson One")
        let second = StudyWorkspaceRecord(courseID: course.id, sequence: 2, title: "Lesson Two")
        context.insert(course)
        context.insert(first)
        context.insert(second)
        try context.save()
        try CourseProgressService.complete(second, context: context)
        XCTAssertEqual(course.currentSequence, 1)
        try CourseProgressService.complete(first, context: context)
        XCTAssertEqual(course.currentSequence, 3)
    }

    func testZeroSequenceFallsBackToValidCourseProgress() {
        XCTAssertEqual(LessonSequenceResolver.infer(fileName: "Day 0.pdf", firstPageText: nil, fallback: 1).sequence, 1)
    }
}
