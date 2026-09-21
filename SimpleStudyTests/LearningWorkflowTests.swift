import XCTest
import SwiftData
@testable import SimpleStudy

@MainActor
final class LearningWorkflowTests: XCTestCase {
    func testEarlyHomeworkIsReconciledAfterReadinessWithoutNavigation() async throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let homework = HomeworkDefinitionRecord(package: HomeworkExampleService.package, sourceFileName: "test")
        let attempt = HomeworkAttemptRecord(homeworkID: homework.id, attemptNumber: 1)
        attempt.state = .submitted
        attempt.submittedAt = Date()
        let todo = TodoRecord(title: "Practice", scheduledAt: Date().addingTimeInterval(3600))
        todo.completionRule = .homeworkSubmission
        todo.homeworkID = homework.id
        todo.actions = [TodoAction(kind: .openHomework, phase: .activation)]
        context.insert(homework)
        context.insert(attempt)
        context.insert(todo)
        try context.save()
        let engine = TodoActionEngine()
        await engine.reconcileLearningCompletion(context: context)
        XCTAssertNil(todo.completedAt)
        todo.originalScheduledAt = Date().addingTimeInterval(-1)
        try context.save()
        await engine.reconcileLearningCompletion(context: context)
        XCTAssertEqual(todo.storedState, .completed)
        XCTAssertNil(engine.navigationRequest)
        await engine.reconcileLearningCompletion(context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TodoRecord>()).count, 1)
    }

    func testDependencyCompletionReconcilesSavedLesson() async throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let course = CourseRecord(title: "Course")
        let workspace = StudyWorkspaceRecord(courseID: course.id, sequence: 1, title: "Lesson")
        let prerequisite = TodoRecord(title: "First", triggerKind: .manual)
        let todo = TodoRecord(title: "Lesson", triggerKind: .dependencyCompletion)
        todo.courseID = course.id
        todo.completionRule = .lessonCompletion
        todo.prerequisiteIDs = [prerequisite.id]
        context.insert(course)
        context.insert(workspace)
        context.insert(prerequisite)
        context.insert(todo)
        try CourseProgressService.complete(workspace, context: context)
        try context.save()
        XCTAssertEqual(todo.workspaceID, workspace.id)
        XCTAssertEqual(course.currentSequence, 2)
        let engine = TodoActionEngine()
        await engine.reconcileLearningCompletion(context: context)
        XCTAssertNil(todo.completedAt)
        await engine.complete(todo: prerequisite, context: context)
        XCTAssertEqual(todo.storedState, .completed)
    }

    func testOldEvidenceCannotCompleteRecurringOccurrence() throws {
        let todo = TodoRecord(title: "Review", scheduledAt: Date())
        todo.recurrence = .daily
        todo.createdAt = Date().addingTimeInterval(-3600)
        XCTAssertFalse(LearningCompletionService.accepts(Date().addingTimeInterval(-86400), for: todo))
        XCTAssertTrue(LearningCompletionService.accepts(Date(), for: todo))
        todo.recurrence = .none
        XCTAssertTrue(LearningCompletionService.accepts(Date().addingTimeInterval(-86400), for: todo))
    }

    func testVocabularyEvidenceSurvivesMissedCompletionCallback() async throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let unit = VocabularyUnitRecord(coursewareID: UUID(), unitKey: "one", sequence: 1, title: "One")
        unit.completedAt = Date()
        let todo = TodoRecord(title: "First learning", triggerKind: .manual)
        todo.completionRule = .vocabularyUnitCompletion
        todo.vocabularyCoursewareID = unit.coursewareID
        todo.vocabularyUnitID = unit.id
        context.insert(unit)
        context.insert(todo)
        try context.save()
        await TodoActionEngine().reconcileLearningCompletion(context: context)
        XCTAssertEqual(todo.storedState, .completed)
    }

    func testRecurringFirstLearningBecomesReviewAndDoesNotReuseEvidence() async throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let unit = VocabularyUnitRecord(coursewareID: UUID(), unitKey: "one", sequence: 1, title: "One")
        let todo = TodoRecord(title: "Words", scheduledAt: Date().addingTimeInterval(-30))
        todo.recurrence = .daily
        todo.completionRule = .vocabularyUnitCompletion
        todo.vocabularyCoursewareID = unit.coursewareID
        todo.vocabularyUnitID = unit.id
        unit.completedAt = Date()
        context.insert(unit)
        context.insert(todo)
        try context.save()
        await TodoActionEngine().complete(todo: todo, context: context)
        let next = try XCTUnwrap(try context.fetch(FetchDescriptor<TodoRecord>()).first { $0.id != todo.id })
        XCTAssertEqual(next.completionRule, .vocabularyReviewSession)
        XCTAssertEqual(next.vocabularyUnitID, unit.id)
        XCTAssertFalse(try LearningCompletionService.hasEvidence(for: next, context: context))
    }

    func testSessionEvidenceRequiresMatchingScope() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let todo = TodoRecord(title: "Review", triggerKind: .manual)
        todo.completionRule = .vocabularyReviewSession
        todo.vocabularyCoursewareID = UUID()
        todo.vocabularyUnitID = UUID()
        context.insert(todo)
        try context.save()
        try LearningCompletionService.recordVocabularySession(coursewareID: todo.vocabularyCoursewareID, unitID: nil, at: Date(), context: context)
        XCTAssertNil(todo.learningEvidenceAt)
        try LearningCompletionService.recordVocabularySession(coursewareID: todo.vocabularyCoursewareID, unitID: todo.vocabularyUnitID, at: Date(), context: context)
        try context.save()
        XCTAssertTrue(try LearningCompletionService.hasEvidence(for: todo, context: context))
    }

    func testStudyAheadDoesNotRunActionsOrCompleteTask() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.container.mainContext
        let course = CourseRecord(title: "Reading")
        let todo = TodoRecord(title: "Study", scheduledAt: Date().addingTimeInterval(3600))
        todo.courseID = course.id
        todo.completionRule = .lessonCompletion
        todo.actions = [TodoAction(kind: .scheduleAlarm, phase: .activation)]
        context.insert(course)
        context.insert(todo)
        try context.save()
        let engine = TodoActionEngine()
        engine.openLearningContent(todo: todo, context: context)
        XCTAssertNotNil(todo.workspaceID)
        XCTAssertNotNil(engine.navigationRequest)
        XCTAssertEqual(todo.actions.first?.state, .pending)
        XCTAssertNil(todo.completedAt)
    }

    func testFuzzyRatingShortensLongInterval() {
        let snapshot = VocabularyLearningSnapshot(firstLearnedAt: Date(), dueAt: Date(), intervalSeconds: 30 * 86400, reviewCount: 6, lapseCount: 0, correctStreak: 4)
        let result = VocabularySpacedRepetition.schedule(snapshot: snapshot, rating: .fuzzy, now: Date())
        XCTAssertLessThan(result.intervalSeconds, snapshot.intervalSeconds)
        XCTAssertLessThanOrEqual(result.intervalSeconds, VocabularySpacedRepetition.oneDay)
        XCTAssertEqual(result.learningState, .learning)
        XCTAssertEqual(result.correctStreak, 0)
    }

    func testWeakWordReturnsOnceWithoutInfiniteSession() {
        let ids = (0..<6).map { _ in UUID() }
        let next = VocabularySessionPlanner.queueAfterRating(.notKnown, itemID: ids[0], queue: ids, index: 0, repeatedIDs: [])
        XCTAssertEqual(next.count, 7)
        XCTAssertEqual(next[4], ids[0])
        let final = VocabularySessionPlanner.queueAfterRating(.notKnown, itemID: ids[0], queue: next, index: 4, repeatedIDs: [ids[0]])
        XCTAssertEqual(final, next)
        XCTAssertEqual(VocabularySessionPlanner.queueAfterRating(.known, itemID: ids[0], queue: ids, index: 0, repeatedIDs: []), ids)
    }
}
