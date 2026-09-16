import Foundation
import SwiftData

enum HomeworkImportError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidJSON(String)
    case unsupportedVersion(Int)
    case emptyIdentifier
    case emptyTitle
    case noQuestions
    case tooManyQuestions
    case duplicateQuestionID(String)
    case invalidQuestion(index: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "Assignment packages must not exceed 5 MB"
        case .invalidJSON(let reason): "Invalid assignment JSON: \(reason)"
        case .unsupportedVersion(let version): "Unsupported schema version \(version); only version 1 is supported"
        case .emptyIdentifier: "Assignment ID is required"
        case .emptyTitle: "Assignment title is required"
        case .noQuestions: "Assignment contains no questions"
        case .tooManyQuestions: "Assignments support up to 1,000 questions"
        case .duplicateQuestionID(let id): "Duplicate question ID: \(id)"
        case .invalidQuestion(let index, let reason): "Question \(index + 1): \(reason)"
        }
    }
}

enum HomeworkImporter {
    static let maximumFileSize = 5_000_000

    static func decodeAndValidate(_ data: Data) throws -> HomeworkPackage {
        guard data.count <= maximumFileSize else { throw HomeworkImportError.fileTooLarge }
        let package: HomeworkPackage
        do {
            package = try JSONCoding.decoder.decode(HomeworkPackage.self, from: data)
        } catch {
            throw HomeworkImportError.invalidJSON(error.localizedDescription)
        }

        guard package.schemaVersion == 1 else { throw HomeworkImportError.unsupportedVersion(package.schemaVersion) }
        guard !package.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HomeworkImportError.emptyIdentifier
        }
        guard !package.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HomeworkImportError.emptyTitle
        }
        guard !package.questions.isEmpty else { throw HomeworkImportError.noQuestions }
        guard package.questions.count <= 1_000 else { throw HomeworkImportError.tooManyQuestions }

        var IDs = Set<String>()
        for (index, question) in package.questions.enumerated() {
            guard !question.id.isEmpty else {
                throw HomeworkImportError.invalidQuestion(index: index, reason: "ID is required")
            }
            guard IDs.insert(question.id).inserted else {
                throw HomeworkImportError.duplicateQuestionID(question.id)
            }
            guard !question.prompt.isEmpty else {
                throw HomeworkImportError.invalidQuestion(index: index, reason: "Question text is required")
            }
            guard question.prompt.count <= 10_000, question.explanation.count <= 20_000 else {
                throw HomeworkImportError.invalidQuestion(index: index, reason: "Question or explanation is too long")
            }
            guard question.points.isFinite, question.points >= 0 else {
                throw HomeworkImportError.invalidQuestion(index: index, reason: "Points must not be negative")
            }

            switch question.type {
            case .singleChoice, .multipleChoice:
                let options = question.options ?? []
                guard options.count >= 2 else {
                    throw HomeworkImportError.invalidQuestion(index: index, reason: "Choice questions need at least two options")
                }
                guard Set(options.map(\.id)).count == options.count else {
                    throw HomeworkImportError.invalidQuestion(index: index, reason: "Option IDs must be unique")
                }
                guard options.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    throw HomeworkImportError.invalidQuestion(index: index, reason: "Option ID and text are required")
                }
                let answer = Set(question.answer.selectedOptionIDs ?? [])
                guard !answer.isEmpty, answer.isSubset(of: Set(options.map(\.id))) else {
                    throw HomeworkImportError.invalidQuestion(index: index, reason: "Correct options are missing or invalid")
                }
                if question.type == .singleChoice && answer.count != 1 {
                    throw HomeworkImportError.invalidQuestion(index: index, reason: "Single-choice questions need exactly one correct option")
                }

            case .fillBlank:
                guard let texts = question.answer.acceptedTexts, !texts.isEmpty, texts.allSatisfy({ !$0.isEmpty }) else {
                    throw HomeworkImportError.invalidQuestion(index: index, reason: "Fill-in-the-blank questions need acceptedTexts")
                }

            case .openResponse:
                guard let reference = question.answer.referenceText, !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw HomeworkImportError.invalidQuestion(index: index, reason: "Open-response questions need referenceText")
                }
            }
        }
        return package
    }
}

enum HomeworkExampleService {
    static var package: HomeworkPackage {
        HomeworkPackage(
            schemaVersion: 1,
            id: "ielts-day-01-homework",
            title: "IELTS Day 01 Practice",
            courseID: "ielts-foundation",
            lessonSequence: 1,
            questions: [
                HomeworkQuestion(
                    id: "q1",
                    type: .singleChoice,
                    prompt: "There ___ considerable debate about this issue.",
                    options: [
                        HomeworkOption(id: "a", text: "is"),
                        HomeworkOption(id: "b", text: "are")
                    ],
                    answer: HomeworkCorrectAnswer(selectedOptionIDs: ["a"]),
                    explanation: "Here, debate is uncountable, so the there-be construction uses is.",
                    points: 1,
                    required: true
                ),
                HomeworkQuestion(
                    id: "q2",
                    type: .multipleChoice,
                    prompt: "Select the expressions that mean to respond.",
                    options: [
                        HomeworkOption(id: "a", text: "react to"),
                        HomeworkOption(id: "b", text: "respond to"),
                        HomeworkOption(id: "c", text: "depend on")
                    ],
                    answer: HomeworkCorrectAnswer(selectedOptionIDs: ["a", "b"]),
                    explanation: "Both react to and respond to describe a response. Select every correct option to earn points.",
                    points: 2,
                    required: true
                ),
                HomeworkQuestion(
                    id: "q3",
                    type: .fillBlank,
                    prompt: "Enter the original word: civilization",
                    answer: HomeworkCorrectAnswer(acceptedTexts: ["civilization"]),
                    explanation: "Answers are case-sensitive and whitespace-sensitive.",
                    points: 1,
                    required: true
                ),
                HomeworkQuestion(
                    id: "q4",
                    type: .openResponse,
                    prompt: "Explain the role of the if-clause in your own words.",
                    answer: HomeworkCorrectAnswer(referenceText: "The if-clause states the condition: if a signal is detected."),
                    explanation: "Open responses are not automatically scored. A reference answer is shown for self-assessment.",
                    points: 0,
                    required: false
                )
            ]
        )
    }

    static func exampleData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(package)
    }
}

enum HomeworkGrader {
    static func grade(package: HomeworkPackage, responses: [String: HomeworkResponse]) -> HomeworkGradeSummary {
        var results: [HomeworkQuestionResult] = []
        var answered = 0
        var correct = 0
        var incorrect = 0
        var objective = 0
        var earned = 0.0

        for question in package.questions {
            let response = responses[question.id] ?? HomeworkResponse()
            if !response.isEmpty { answered += 1 }

            let outcome: HomeworkQuestionOutcome
            let points: Double
            switch question.type {
            case .singleChoice, .multipleChoice:
                objective += 1
                if response.isEmpty {
                    outcome = .unanswered
                    points = 0
                    incorrect += 1
                } else if Set(response.selectedOptionIDs) == Set(question.answer.selectedOptionIDs ?? []) {
                    outcome = .correct
                    points = question.points
                    correct += 1
                } else {
                    outcome = .incorrect
                    points = 0
                    incorrect += 1
                }

            case .fillBlank:
                objective += 1
                if response.isEmpty {
                    outcome = .unanswered
                    points = 0
                    incorrect += 1
                } else if (question.answer.acceptedTexts ?? []).contains(response.text) {
                    outcome = .correct
                    points = question.points
                    correct += 1
                } else {
                    outcome = .incorrect
                    points = 0
                    incorrect += 1
                }

            case .openResponse:
                outcome = response.isEmpty ? .unanswered : .awaitingSelfReview
                points = 0
            }
            earned += points
            results.append(.init(questionID: question.id, outcome: outcome, earnedPoints: points))
        }

        return HomeworkGradeSummary(
            totalQuestions: package.questions.count,
            answeredQuestions: answered,
            correctObjectiveQuestions: correct,
            incorrectObjectiveQuestions: incorrect,
            objectiveQuestions: objective,
            earnedPoints: earned,
            possiblePoints: package.questions
                .filter { $0.type != .openResponse }
                .reduce(0) { $0 + $1.points },
            results: results
        )
    }
}

@MainActor
enum HomeworkAttemptService {
    static func currentOrLatest(for homeworkID: UUID, context: ModelContext) throws -> HomeworkAttemptRecord {
        let attempts = try context.fetch(FetchDescriptor<HomeworkAttemptRecord>())
            .filter { $0.homeworkID == homeworkID }
        if let draft = attempts.filter({ $0.state == .draft }).max(by: { $0.attemptNumber < $1.attemptNumber }) { return draft }
        if let submitted = attempts
            .filter({ $0.state == .submitted })
            .sorted(by: { ($0.submittedAt ?? .distantPast) > ($1.submittedAt ?? .distantPast) })
            .first {
            return submitted
        }
        let nextNumber = (attempts.map(\.attemptNumber).max() ?? 0) + 1
        let attempt = HomeworkAttemptRecord(homeworkID: homeworkID, attemptNumber: nextNumber)
        context.insert(attempt)
        do { try context.save() } catch { context.rollback(); throw error }
        return attempt
    }

    static func submit(
        attempt: HomeworkAttemptRecord,
        package: HomeworkPackage,
        responses: [String: HomeworkResponse],
        context: ModelContext
    ) throws {
        guard attempt.state == .draft else { throw HomeworkAttemptError.alreadySubmitted }
        let missing = package.questions.filter { $0.required && (responses[$0.id] ?? HomeworkResponse()).isEmpty }
        guard missing.isEmpty else { throw HomeworkAttemptError.requiredAnswers(missing.count) }
        attempt.answers = responses
        let grade = HomeworkGrader.grade(package: package, responses: responses)
        attempt.gradeData = JSONCoding.encode(grade)
        attempt.state = .submitted
        attempt.submittedAt = Date()
        attempt.updatedAt = Date()

        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func reset(homeworkID: UUID, context: ModelContext) throws -> HomeworkAttemptRecord {
        let attempts = try context.fetch(FetchDescriptor<HomeworkAttemptRecord>())
            .filter { $0.homeworkID == homeworkID }
        for draft in attempts where draft.state == .draft { context.delete(draft) }
        let nextNumber = (attempts.map(\.attemptNumber).max() ?? 0) + 1
        let newAttempt = HomeworkAttemptRecord(homeworkID: homeworkID, attemptNumber: nextNumber)
        context.insert(newAttempt)
        do { try context.save() } catch { context.rollback(); throw error }
        return newAttempt
    }
}

enum HomeworkAttemptError: LocalizedError {
    case alreadySubmitted
    case requiredAnswers(Int)

    var errorDescription: String? {
        switch self {
        case .alreadySubmitted: "This attempt has been submitted. Start a new attempt to practice again."
        case .requiredAnswers(let count): "Answer the remaining \(count) required questions before submitting."
        }
    }
}
