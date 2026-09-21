import XCTest
import SwiftData
@testable import SimpleStudy

@MainActor
final class ProductLogicTests: XCTestCase {
    func testEnglishInterfacePreservesChineseLessonFilenameRecognition() {
        let inference = LessonSequenceResolver.infer(
            fileName: "\u{7b2c} 12 \u{8bfe}.pdf",
            firstPageText: "",
            fallback: 1
        )
        XCTAssertEqual(inference.sequence, 12)
        XCTAssertEqual(inference.evidence, "Lesson order found in the filename")
    }

    func testSequenceResolverPrefersFilename() {
        let inference = LessonSequenceResolver.infer(
            fileName: "IELTS Day 27.pdf",
            firstPageText: "Lesson 3",
            fallback: 1
        )
        XCTAssertEqual(inference.sequence, 27)
        XCTAssertGreaterThan(inference.confidence, 0.9)
    }

    func testDependencyKeepsTodoWaiting() {
        let prerequisite = TodoRecord(title: "Complete first")
        let dependent = TodoRecord(
            title: "Complete next",
            triggerKind: .dependencyCompletion,
            scheduledAt: Date().addingTimeInterval(86_400)
        )
        dependent.prerequisiteIDs = [prerequisite.id]

        XCTAssertEqual(
            TodoStateResolver.state(for: dependent, allTodos: [prerequisite, dependent]),
            .waitingDependency
        )

        prerequisite.storedState = .completed
        XCTAssertEqual(
            TodoStateResolver.state(for: dependent, allTodos: [prerequisite, dependent]),
            .ready
        )
    }

    func testWorkflowPlannerPrioritizesRecoveryBeforeRoutineWork() {
        let routine = TodoRecord(title: "Read the lesson", triggerKind: .manual)
        let overdue = TodoRecord(
            title: "Finish the exercise",
            triggerKind: .scheduledTime,
            scheduledAt: Date().addingTimeInterval(-3_600)
        )
        let failed = TodoRecord(title: "Prepare the materials", triggerKind: .manual)
        failed.storedState = .partialFailure

        let step = TodoWorkflowPlanner.nextStep(
            activeTodos: [routine, overdue, failed],
            allTodos: [routine, overdue, failed]
        )

        XCTAssertEqual(step?.todo.id, failed.id)
        XCTAssertEqual(step?.state, .partialFailure)
    }

    func testWorkflowPlannerExplainsBlockedTask() {
        let prerequisite = TodoRecord(title: "Read the lesson", triggerKind: .manual)
        let dependent = TodoRecord(title: "Write the summary", triggerKind: .dependencyCompletion)
        dependent.prerequisiteIDs = [prerequisite.id]

        let step = TodoWorkflowPlanner.nextStep(
            activeTodos: [dependent],
            allTodos: [prerequisite, dependent]
        )

        XCTAssertEqual(step?.state, .waitingDependency)
        XCTAssertEqual(step?.waitingFor, [prerequisite.title])
    }

    func testDeletingTodoRemovesRecordAndUnlinksDependents() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let prerequisite = TodoRecord(title: "Completed prerequisite")
        prerequisite.storedState = .completed
        let dependent = TodoRecord(
            title: "Next task",
            triggerKind: .dependencyCompletion,
            scheduledAt: Date().addingTimeInterval(3600)
        )
        dependent.prerequisiteIDs = [prerequisite.id]
        let registration = AlarmRegistrationRecord(
            todoID: prerequisite.id,
            deviceID: "test-device",
            deviceKind: "iPhone",
            fireDate: prerequisite.originalScheduledAt
        )

        context.insert(prerequisite)
        context.insert(dependent)
        context.insert(registration)
        try context.save()

        let engine = TodoActionEngine()
        try await engine.delete(todo: prerequisite, context: context)

        let todos = try context.fetch(FetchDescriptor<TodoRecord>())
        let registrations = try context.fetch(FetchDescriptor<AlarmRegistrationRecord>())
        XCTAssertFalse(todos.contains(where: { $0.id == prerequisite.id }))
        XCTAssertEqual(todos.first(where: { $0.id == dependent.id })?.prerequisiteIDs, [])
        XCTAssertEqual(todos.first(where: { $0.id == dependent.id })?.storedState, .ready)
        XCTAssertFalse(registrations.contains(where: { $0.todoID == prerequisite.id }))
    }

    func testCancellingAlarmRegistrationKeepsTodoAndConfiguration() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = TodoRecord(
            title: "Morning study",
            triggerKind: .scheduledTime,
            scheduledAt: Date().addingTimeInterval(3600)
        )
        var alarmAction = TodoAction(
            kind: .scheduleAlarm,
            phase: .activation,
            parameters: .init(alarmTarget: .iPhone)
        )
        alarmAction.state = .succeeded
        todo.actions = [alarmAction]
        todo.alarmState = .scheduled

        let registration = AlarmRegistrationRecord(
            todoID: todo.id,
            deviceID: DeviceIdentity.id,
            deviceKind: DeviceIdentity.kind,
            fireDate: todo.originalScheduledAt
        )
        registration.state = .scheduled
        context.insert(todo)
        context.insert(registration)
        try context.save()

        let engine = TodoActionEngine()
        try await engine.cancelAlarmRegistration(registration, context: context)

        XCTAssertEqual(registration.state, .stopped)
        XCTAssertEqual(todo.alarmState, .stopped)
        XCTAssertTrue(todo.actions.first?.isEnabled == true)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TodoRecord>()).contains { $0.id == todo.id })
    }

    func testDeletingAlarmSettingDisablesAlarmWithoutDeletingTodo() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = TodoRecord(
            title: "Prepare materials",
            triggerKind: .scheduledTime,
            scheduledAt: Date().addingTimeInterval(3600)
        )
        var alarmAction = TodoAction(
            kind: .scheduleAlarm,
            phase: .activation,
            parameters: .init(alarmTarget: .iPhone)
        )
        alarmAction.state = .succeeded
        todo.actions = [alarmAction]

        let registration = AlarmRegistrationRecord(
            todoID: todo.id,
            deviceID: DeviceIdentity.id,
            deviceKind: DeviceIdentity.kind,
            fireDate: todo.originalScheduledAt
        )
        registration.state = .scheduled
        context.insert(todo)
        context.insert(registration)
        try context.save()

        let engine = TodoActionEngine()
        try await engine.deleteAlarmRegistration(registration, context: context)

        let todos = try context.fetch(FetchDescriptor<TodoRecord>())
        let registrations = try context.fetch(FetchDescriptor<AlarmRegistrationRecord>())
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos.first?.id, todo.id)
        XCTAssertEqual(todos.first?.alarmState, .notRequested)
        XCTAssertEqual(todos.first?.actions.first?.state, .skipped)
        XCTAssertFalse(todos.first?.actions.first?.isEnabled == true)
        XCTAssertTrue(registrations.isEmpty)

        await engine.processPendingDeviceAlarms(context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AlarmRegistrationRecord>()).isEmpty)
    }

    func testReminderPlannerUsesOneMainReminderForAutomaticOnlyTodo() {
        let todo = TodoRecord(
            title: "Prepare materials",
            triggerKind: .scheduledTime,
            scheduledAt: Date().addingTimeInterval(3600)
        )
        todo.actions = [
            TodoAction(kind: .createNote, phase: .activation, isCritical: false),
            TodoAction(kind: .scheduleAlarm, phase: .activation, isCritical: false),
            TodoAction(kind: .localNotification, phase: .activation, isCritical: false)
        ]

        let reminders = TodoReminderPlanner.descriptors(for: todo)

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.actionID, nil)
        XCTAssertEqual(reminders.first?.title, todo.title)
        XCTAssertEqual(reminders.first?.dueDate, todo.originalScheduledAt)
    }

    func testReminderPlannerCreatesOneReminderPerHumanContentStep() {
        let todo = TodoRecord(title: "Complete today's study")
        let studyAction = TodoAction(kind: .openStudy, phase: .activation, isCritical: false)
        let homeworkAction = TodoAction(kind: .openHomework, phase: .completion, isCritical: false)
        todo.actions = [
            TodoAction(kind: .createNote, phase: .activation, isCritical: false),
            studyAction,
            homeworkAction
        ]

        let reminders = TodoReminderPlanner.descriptors(for: todo)

        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.map(\.actionID), [studyAction.id, homeworkAction.id])
        XCTAssertEqual(reminders.map(\.title), ["Study: Complete today's study", "Practice: Complete today's study"])
        XCTAssertTrue(reminders.allSatisfy { $0.notes.contains(todo.id.uuidString) })
    }

    func testNotificationPlannerMirrorsHumanContentSteps() {
        let todo = TodoRecord(title: "Complete today's study", details: "Complete the task and record the result.")
        let studyAction = TodoAction(kind: .openStudy, phase: .activation, isCritical: false)
        let homeworkAction = TodoAction(kind: .openHomework, phase: .activation, isCritical: false)
        todo.actions = [studyAction, homeworkAction]

        let notifications = TodoNotificationPlanner.descriptors(for: todo)

        XCTAssertEqual(notifications.count, 2)
        XCTAssertEqual(notifications.map(\.actionID), [studyAction.id, homeworkAction.id])
        XCTAssertTrue(notifications.allSatisfy { $0.body == todo.details })
        XCTAssertEqual(
            notifications.map(\.title),
            ["Study: Complete today's study", "Practice: Complete today's study"]
        )
    }

    func testNotificationPlannerDoesNotDuplicateConfiguredNotificationAction() {
        let todo = TodoRecord(title: "Scheduled reminder")
        todo.actions = [
            TodoAction(
                kind: .localNotification,
                phase: .activation,
                isCritical: false,
                parameters: .init(message: "Custom reminder message")
            )
        ]

        XCTAssertTrue(TodoNotificationPlanner.descriptors(for: todo).isEmpty)
    }

    func testMultipleChoiceRequiresExactSetAndFillBlankIsStrict() {
        let package = HomeworkPackage(
            schemaVersion: 1,
            id: "test",
            title: "Test",
            questions: [
                HomeworkQuestion(
                    id: "multi",
                    type: .multipleChoice,
                    prompt: "Multiple choice",
                    options: [
                        HomeworkOption(id: "a", text: "A"),
                        HomeworkOption(id: "b", text: "B"),
                        HomeworkOption(id: "c", text: "C")
                    ],
                    answer: HomeworkCorrectAnswer(selectedOptionIDs: ["a", "b"]),
                    explanation: "",
                    points: 2,
                    required: true
                ),
                HomeworkQuestion(
                    id: "fill",
                    type: .fillBlank,
                    prompt: "Fill in the blank",
                    answer: HomeworkCorrectAnswer(acceptedTexts: ["Answer"]),
                    explanation: "",
                    points: 1,
                    required: true
                )
            ]
        )

        let grade = HomeworkGrader.grade(package: package, responses: [
            "multi": HomeworkResponse(selectedOptionIDs: ["a", "b", "c"]),
            "fill": HomeworkResponse(text: "answer")
        ])

        XCTAssertEqual(grade.correctObjectiveQuestions, 0)
        XCTAssertEqual(grade.incorrectObjectiveQuestions, 2)
        XCTAssertEqual(grade.earnedPoints, 0)
    }

    func testOpenResponseIsExcludedFromObjectiveAccuracy() {
        let package = HomeworkPackage(
            schemaVersion: 1,
            id: "open",
            title: "Open response",
            questions: [
                HomeworkQuestion(
                    id: "q",
                    type: .openResponse,
                    prompt: "Description",
                    answer: HomeworkCorrectAnswer(referenceText: "Reference"),
                    explanation: "",
                    points: 5,
                    required: true
                )
            ]
        )
        let grade = HomeworkGrader.grade(
            package: package,
            responses: ["q": HomeworkResponse(text: "My answer")]
        )

        XCTAssertEqual(grade.objectiveQuestions, 0)
        XCTAssertEqual(grade.possiblePoints, 0)
        XCTAssertEqual(grade.results.first?.outcome, .awaitingSelfReview)
    }

    func testHomeworkImporterAcceptsValidPackageAndRejectsDuplicateQuestionIDs() throws {
        let question = HomeworkQuestion(
            id: "q1",
            type: .fillBlank,
            prompt: "Fill",
            answer: HomeworkCorrectAnswer(acceptedTexts: ["Answer"]),
            explanation: "Because.",
            points: 1,
            required: true
        )
        let valid = HomeworkPackage(
            schemaVersion: 1,
            id: "day-1",
            title: "Day 1",
            questions: [question]
        )
        let decoded = try HomeworkImporter.decodeAndValidate(JSONCoding.encoder.encode(valid))
        XCTAssertEqual(decoded.id, valid.id)

        let invalid = HomeworkPackage(
            schemaVersion: 1,
            id: "duplicate",
            title: "Duplicate",
            questions: [question, question]
        )
        XCTAssertThrowsError(try HomeworkImporter.decodeAndValidate(JSONCoding.encoder.encode(invalid))) { error in
            XCTAssertEqual(error as? HomeworkImportError, .duplicateQuestionID("q1"))
        }
    }

    func testShortcutActionParametersRoundTrip() throws {
        let action = TodoAction(
            kind: .runShortcut,
            phase: .activation,
            parameters: TodoActionParameters(shortcutName: "Create IELTS Study Notes")
        )
        let decoded = try JSONCoding.decoder.decode(
            TodoAction.self,
            from: JSONCoding.encoder.encode(action)
        )
        XCTAssertEqual(decoded.kind, .runShortcut)
        XCTAssertEqual(decoded.parameters.shortcutName, "Create IELTS Study Notes")
    }

    func testNoteTemplateExamplePassesValidation() throws {
        let data = try NoteTemplatePackageService.exampleData()
        let package = try NoteTemplatePackageService.decodeAndValidate(data)

        XCTAssertEqual(package.schemaVersion, 1)
        XCTAssertEqual(package.name, "Sentence Study")
        XCTAssertEqual(package.blocks.count, 5)
    }

    func testNoteTemplateRejectsDuplicateBlockIDs() throws {
        let block = NoteBlock(kind: .richText, title: "Body")
        let package = NoteTemplatePackage(
            schemaVersion: 1,
            name: "Duplicate ID",
            details: "",
            sourceVersion: 1,
            blocks: [block, block]
        )

        XCTAssertThrowsError(
            try NoteTemplatePackageService.decodeAndValidate(JSONCoding.encoder.encode(package))
        ) { error in
            XCTAssertEqual(error as? NoteTemplateImportError, .duplicateBlockID)
        }
    }

    func testAppSettingsPersistDeviceDefaults() {
        let suiteName = "SimpleStudyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let templateID = UUID()
        let first = AppSettings(defaults: defaults)
        first.isICloudEnabled = false
        first.appearance = .dark
        first.defaultAlarmTarget = .allAuthorizedDevices
        first.defaultMissedPolicy = .accumulate
        first.defaultTemplateID = templateID

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.isICloudEnabled)
        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertEqual(reloaded.defaultAlarmTarget, .allAuthorizedDevices)
        XCTAssertEqual(reloaded.defaultMissedPolicy, .accumulate)
        XCTAssertEqual(reloaded.defaultTemplateID, templateID)
    }

    func testMarkdownDecoderNormalizesBOMAndWindowsLineEndings() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("# Title\r\n\r\n> **Content**\r\n".utf8))

        let decoded = try NoteMarkdownService.decode(data)

        XCTAssertEqual(decoded, "# Title\n\n> **Content**\n")
    }

    func testMarkdownFormatWrapsSelectedText() {
        let result = NoteMarkdownService.apply(
            .bold,
            to: "Sentence",
            selectedCharacterRange: 0..<8
        )

        XCTAssertEqual(result.content, "**Sentence**")
        XCTAssertEqual(result.selectedCharacterRange, 2..<10)
    }

    func testDictionarySelectionQueryAcceptsShortWordOrPhrase() {
        XCTAssertEqual(
            DictionarySelectionQuery.normalized(from: "  There\n is  "),
            "there is"
        )
        XCTAssertEqual(
            DictionarySelectionQuery.normalized(from: "\u{77e9}\u{9635}"),
            "\u{77e9}\u{9635}"
        )
    }

    func testDictionarySelectionQueryRejectsLongOrNonTextSelection() {
        XCTAssertNil(DictionarySelectionQuery.normalized(from: "one two three four five six seven"))
        XCTAssertNil(DictionarySelectionQuery.normalized(from: "12345"))
        XCTAssertNil(DictionarySelectionQuery.normalized(from: String(repeating: "\u{5b57}", count: 17)))
    }

    func testDailyLearningTemplateRendersRequestedMarkdownStructure() {
        let template = NoteTemplateRecord(
            name: "Sentence study",
            details: "",
            blocks: NoteTemplatePackageService.examplePackage.blocks
        )

        let content = NoteRenderingService.render(
            template: template,
            courseTitle: "IELTS",
            day: 2,
            materialName: nil
        )

        XCTAssertTrue(content.hasPrefix("# 📝Day 2   📆"))
        XCTAssertTrue(content.contains("> **• 📚Sentence**\n>"))
        XCTAssertTrue(content.contains("> **• 📔Words and Expressions**\n>"))
        XCTAssertTrue(content.contains("> **• 📝Grammar**\n>"))
        XCTAssertTrue(content.contains("> **• ✅Output**\n>"))
    }

    func testStarterTemplateMigrationUpdatesOnlyUntouchedBuiltIns() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let oldSentence = NoteTemplateRecord(
            name: "Sentence study",
            details: "Old format",
            blocks: [NoteBlock(kind: .richText, title: "Old body")],
            isStarter: true
        )
        let editedPDF = NoteTemplateRecord(
            name: "PDF study",
            details: "User edited",
            blocks: [NoteBlock(kind: .richText, title: "My format")],
            isStarter: true
        )
        editedPDF.version = 2
        context.insert(oldSentence)
        context.insert(editedPDF)
        try context.save()

        StarterDataService.bootstrapIfNeeded(in: context)

        let templates = try context.fetch(FetchDescriptor<NoteTemplateRecord>())
        XCTAssertEqual(templates.filter(\.isStarter).count, 5)
        XCTAssertEqual(oldSentence.version, 2)
        XCTAssertEqual(oldSentence.blocks.first?.title, "📝Day {{day}}   📆{{date}}")
        XCTAssertEqual(editedPDF.version, 2)
        XCTAssertEqual(editedPDF.details, "User edited")
        XCTAssertEqual(editedPDF.blocks.first?.title, "My format")
    }

    func testTodoCreationVocabularyIsGenericAndBeginnerSafe() {
        XCTAssertEqual(
            TodoQuickPlan.allCases.map(\.title),
            ["Simple task", "Scheduled reminder", "Alarm", "Open linked content", "Task sequence", "Repeating task", "Custom workflow"]
        )
        XCTAssertEqual(
            TodoKind.allCases.map(\.title),
            ["General", "Organize materials", "Study session", "Memory practice", "Practice"]
        )
        XCTAssertFalse(TodoTriggerKind.creationOptions.contains(.courseProgress))
        XCTAssertFalse(TodoActionKind.creationOptions.contains(.vocabularyReminder))
    }

    func testVocabularyCoursewareExamplePassesValidation() throws {
        let data = try VocabularyCoursewareService.exampleData()
        let package = try VocabularyCoursewareService.decodeAndValidate(data)

        XCTAssertEqual(package.schemaVersion, 1)
        XCTAssertEqual(package.type, "vocabulary-courseware")
        XCTAssertEqual(package.units.count, 2)
        XCTAssertEqual(package.units.reduce(0) { $0 + $1.items.count }, 3)
    }

    func testFlatVocabularySourceCanBeGroupedBeforeImport() throws {
        let flatJSON = """
        {
          "schemaVersion": 1,
          "type": "vocabulary-courseware",
          "id": "flat-source",
          "title": "Ungrouped list",
          "items": [
            { "term": "one", "meaning": "\u{4e00}" },
            { "term": "two", "meaning": "\u{4e8c}" },
            { "term": "three", "meaning": "\u{4e09}" }
          ]
        }
        """

        let package = try VocabularyCoursewareService.decodeAndValidate(Data(flatJSON.utf8))
        XCTAssertFalse(package.sourceHasExplicitUnits)
        XCTAssertEqual(package.units.count, 1)

        let grouped = package.regrouped(for: .fixedSize, chunkSize: 2)
        XCTAssertEqual(grouped.units.count, 2)
        XCTAssertEqual(grouped.units.map { $0.items.count }, [2, 1])
        XCTAssertEqual(grouped.units.map(\.sequence), [1, 2])
    }

    func testVocabularyImporterRejectsDuplicateUnitKeys() throws {
        let package = VocabularyCoursewarePackage(
            id: "duplicate-units",
            title: "Duplicate groups",
            units: [
                VocabularyUnitPackage(key: "same", sequence: 1, title: "Group One", items: [VocabularyItemPackage(term: "one")]),
                VocabularyUnitPackage(key: "same", sequence: 2, title: "Group Two", items: [VocabularyItemPackage(term: "two")])
            ]
        )

        XCTAssertThrowsError(
            try VocabularyCoursewareService.decodeAndValidate(JSONCoding.encode(package))
        ) { error in
            XCTAssertEqual(error as? VocabularyImportError, .duplicateUnitKey("same"))
        }
    }

    func testVocabularySchedulerUsesRatingsAndFirstRatingCompletesLearning() {
        let now = Date(timeIntervalSince1970: 10_000)
        let newSnapshot = VocabularyLearningSnapshot(
            firstLearnedAt: nil,
            dueAt: nil,
            intervalSeconds: 0,
            reviewCount: 0,
            lapseCount: 0,
            correctStreak: 0
        )

        let fuzzy = VocabularySpacedRepetition.schedule(snapshot: newSnapshot, rating: .fuzzy, now: now)
        XCTAssertEqual(fuzzy.learningState, .learning)
        XCTAssertEqual(fuzzy.firstLearnedAt, now)
        XCTAssertEqual(fuzzy.reviewCount, 1)
        XCTAssertEqual(fuzzy.dueAt, now.addingTimeInterval(VocabularySpacedRepetition.oneDay))

        let known = VocabularySpacedRepetition.schedule(
            snapshot: VocabularyLearningSnapshot(
                firstLearnedAt: now,
                dueAt: now,
                intervalSeconds: VocabularySpacedRepetition.oneDay,
                reviewCount: 1,
                lapseCount: 0,
                correctStreak: 0
            ),
            rating: .known,
            now: now.addingTimeInterval(VocabularySpacedRepetition.oneDay)
        )
        XCTAssertEqual(known.learningState, .review)
        XCTAssertGreaterThan(known.intervalSeconds, VocabularySpacedRepetition.oneDay)
        XCTAssertEqual(known.correctStreak, 1)
    }

    func testVocabularyReviewCompletesUnitByFirstLearningNotByWordCount() throws {
        let package = VocabularyCoursewarePackage(
            id: "review-test",
            title: "Review test",
            units: [
                VocabularyUnitPackage(
                    key: "lesson-a",
                    sequence: 1,
                    title: "Lesson A",
                    expectedCount: 99,
                    items: [
                        VocabularyItemPackage(key: "a", term: "alpha", meaning: "\u{963f}\u{5c14}\u{6cd5}"),
                        VocabularyItemPackage(key: "b", term: "beta", meaning: "\u{8d1d}\u{5854}")
                    ]
                )
            ]
        )
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        _ = try VocabularyCoursewareService.importPackage(
            package,
            sourceFileName: "review-test.json",
            context: context
        )

        let courseware = try XCTUnwrap(
            try context.fetch(FetchDescriptor<VocabularyCoursewareRecord>()).first
        )
        let unit = try XCTUnwrap(
            try context.fetch(FetchDescriptor<VocabularyUnitRecord>()).first
        )
        var items = try context.fetch(FetchDescriptor<VocabularyItemRecord>())
            .sorted { $0.order < $1.order }

        XCTAssertNil(courseware.completedAt)
        XCTAssertNil(unit.completedAt)

        _ = try VocabularyReviewService.record(rating: .notKnown, for: items[0], context: context)
        XCTAssertFalse(try VocabularyReviewService.progress(for: unit, context: context).isComplete)
        XCTAssertNil(unit.completedAt)

        _ = try VocabularyReviewService.record(rating: .known, for: items[1], context: context)
        XCTAssertNotNil(unit.completedAt)
        XCTAssertNotNil(courseware.completedAt)
        XCTAssertEqual(try VocabularyReviewService.progress(for: unit, context: context).firstLearnedCount, 2)

        items = try context.fetch(FetchDescriptor<VocabularyItemRecord>())
        XCTAssertEqual(items.filter { $0.firstLearnedAt != nil }.count, 2)
        XCTAssertEqual(items.first(where: { $0.sourceItemKey == "a" })?.learningState, .learning)
    }

    func testVocabularyTodoCompletionTargetsUnit() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let coursewareID = UUID()
        let unit = VocabularyUnitRecord(coursewareID: coursewareID, unitKey: "unit", sequence: 1, title: "Unit")
        unit.completedAt = Date()
        context.insert(unit)
        let unitID = unit.id
        let todo = TodoRecord(title: "Complete vocabulary unit", triggerKind: .manual)
        todo.completionRule = .vocabularyUnitCompletion
        todo.vocabularyCoursewareID = coursewareID
        todo.vocabularyUnitID = unitID
        context.insert(todo)
        try context.save()

        await TodoActionEngine().completeVocabularyTasks(
            coursewareID: coursewareID,
            unitID: unitID,
            context: context
        )

        XCTAssertEqual(todo.storedState, .completed)
    }

    func testLocalDictionaryLookupOnlyReturnsExactOrPrefixWordAndPhraseMatches() throws {
        let package = LocalDictionaryPackage(
            id: "test-dictionary",
            title: "Test dictionary",
            entries: [
                LocalDictionaryEntry(headword: "review", definition: "\u{590d}\u{4e60}"),
                LocalDictionaryEntry(headword: "review board", definition: "\u{5ba1}\u{67e5}\u{59d4}\u{5458}\u{4f1a}"),
                LocalDictionaryEntry(headword: "prepare", definition: "\u{51c6}\u{5907}")
            ]
        )
        let decoded = try JSONCoding.decoder.decode(
            LocalDictionaryPackage.self,
            from: JSONCoding.encoder.encode(package)
        )

        XCTAssertEqual(decoded, package)
        XCTAssertEqual(
            LocalDictionaryLookup.result(for: "REVIEW BOARD", entries: package.entries),
            .matches([package.entries[1]])
        )
        XCTAssertEqual(
            LocalDictionaryLookup.result(for: "pre", entries: package.entries),
            .matches([package.entries[2]])
        )
        XCTAssertEqual(
            LocalDictionaryLookup.result(for: "\u{590d}\u{4e60}", entries: package.entries),
            .matches([package.entries[0]])
        )
        if case .matches(let reviewResults) = LocalDictionaryLookup.result(for: "review", entries: package.entries) {
            XCTAssertEqual(reviewResults.map(\.headword), ["review", "review board"])
        } else {
            XCTFail("Lookup should return both the word and phrases containing it")
        }
        XCTAssertEqual(
            LocalDictionaryLookup.result(
                for: "this is a complete sentence that should not be translated",
                entries: package.entries
            ),
            .invalidSelection
        )
    }

    func testDictionaryNormalizerHandlesSelectionPunctuationAndApostrophes() {
        XCTAssertEqual(
            DictionaryTextNormalizer.normalize("  DON’T   stop!  "),
            "don't stop"
        )
        XCTAssertEqual(DictionaryTextNormalizer.tokenCount("good morning."), 2)
        XCTAssertEqual(DictionaryTextNormalizer.normalize("  !!! "), "")
    }

    func testLocalDictionaryMergeKeepsPersonalResultsFirst() {
        let personal = LocalDictionaryEntry(
            id: "personal-review",
            headword: "review",
            definition: "My study definition",
            sourceName: "My dictionary"
        )
        let publicEntry = LocalDictionaryEntry(
            id: "public-42",
            headword: "review",
            definition: "\u{590d}\u{4e60}",
            sourceName: "Public dictionary"
        )

        let result = LocalDictionaryLookup.merged(
            .matches([personal]),
            .matches([publicEntry])
        )

        XCTAssertEqual(result, .matches([personal, publicEntry]))
    }

    func testDictionaryEntryPreservesPronunciationAndEnrichmentFields() throws {
        let entry = LocalDictionaryEntry(
            id: "abandon",
            headword: "abandon",
            pronunciationUS: "/əˈbændən/",
            pronunciationUK: "/ɐbˈændən/",
            partOfSpeech: "v.",
            definition: "\u{653e}\u{5f03}",
            englishDefinition: "to leave completely",
            example: "They abandoned the plan.",
            synonyms: "leave",
            antonyms: "keep",
            forms: "abandoned, abandoning",
            frequency: 120,
            tags: "IELTS",
            sourceName: "ECDICT · IPA-Dict"
        )
        let package = LocalDictionaryPackage(
            id: "enriched",
            title: "Rich dictionary",
            entries: [entry],
            entryCount: 1,
            sourceSummary: "Public source"
        )

        let decoded = try JSONCoding.decoder.decode(
            LocalDictionaryPackage.self,
            from: JSONCoding.encoder.encode(package)
        )

        XCTAssertEqual(decoded, package)
        XCTAssertEqual(decoded.entries.first?.primaryPronunciation, "/əˈbændən/")
        XCTAssertEqual(decoded.totalEntryCount, 1)
    }

    func testDictionaryStructuredDetailsAndFallbackSenseParsing() throws {
        let entry = LocalDictionaryEntry(
            id: "matrix",
            headword: "matrix",
            partOfSpeech: "n.",
            definition: "\u{6bcd}\u{4f53}\u{FF1B}\u{57fa}\u{8d28}\u{FF1B}\u{77e9}\u{9635}",
            senses: [
                LocalDictionarySense(
                    id: "matrix-1",
                    partOfSpeech: "n.",
                    translation: "\u{6bcd}\u{4f53}\u{FF1B}\u{57fa}\u{8d28}"
                )
            ],
            phrases: [
                LocalDictionaryPhrase(
                    id: "matrix-algebra",
                    expression: "matrix algebra",
                    translation: "\u{77e9}\u{9635}\u{4ee3}\u{6570}",
                    kind: "phrase"
                )
            ]
        )
        let package = LocalDictionaryPackage(id: "structured", title: "Structured dictionary", entries: [entry])
        let decoded = try JSONCoding.decoder.decode(
            LocalDictionaryPackage.self,
            from: JSONCoding.encoder.encode(package)
        )

        XCTAssertEqual(decoded, package)
        XCTAssertEqual(decoded.entries.first?.senses.first?.partOfSpeech, "n.")
        XCTAssertEqual(decoded.entries.first?.phrases.first?.translation, "\u{77e9}\u{9635}\u{4ee3}\u{6570}")

        let fallback = LocalDictionaryEntry(
            headword: "matrix",
            partOfSpeech: "n:100",
            definition: "n. \u{6bcd}\u{4f53}, \u{5b50}\u{5bab}\n[\u{8ba1}] \u{77e9}\u{9635}",
            englishDefinition: "n. a rectangular array"
        )
        let senses = LocalDictionarySenseParser.senses(for: fallback)
        XCTAssertEqual(senses.map(\.translation), ["\u{6bcd}\u{4f53}", "\u{5b50}\u{5bab}", "\u{77e9}\u{9635}"])
        XCTAssertEqual(senses.map(\.partOfSpeech), ["n.", "n.", "n."])
        XCTAssertEqual(senses.last?.note, "\u{8ba1}")
    }

    func testLocalDictionaryStorePersistsImportedPackLocally() throws {
        let indexURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleStudyDictionary-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: indexURL) }
        let sourceDirectoryURL = indexURL.deletingPathExtension().appendingPathExtension("packs")
        defer { try? FileManager.default.removeItem(at: sourceDirectoryURL) }

        let package = LocalDictionaryPackage(
            id: "persisted",
            title: "Persistence test",
            entries: [LocalDictionaryEntry(headword: "persist", definition: "\u{6301}\u{4e45}\u{4fdd}\u{5b58}")]
        )
        let store = LocalDictionaryStore(indexURL: indexURL)
        let sourceData = try JSONCoding.encoder.encode(package)
        _ = try store.importPackage(data: sourceData)

        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: sourceDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(sourceFiles.count, 1)
        XCTAssertEqual(try Data(contentsOf: sourceFiles[0]), sourceData)

        let reloaded = LocalDictionaryStore(indexURL: indexURL)
        XCTAssertEqual(reloaded.packs.first(where: { $0.id == "persisted" })?.title, "Persistence test")
        XCTAssertEqual(reloaded.lookup("persist").matchesCount, 1)
    }

    func testOpenStudyActionWorksWithoutEnglishCourseAssociation() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = TodoRecord(title: "Read a book", triggerKind: .manual)
        todo.actions = [TodoAction(kind: .openStudy, phase: .activation, isCritical: false)]
        context.insert(todo)
        try context.save()

        let engine = TodoActionEngine()
        await engine.activate(todo: todo, context: context)

        XCTAssertEqual(engine.navigationRequest, .study(nil))
        XCTAssertEqual(todo.actions.first?.state, .succeeded)
    }
}
