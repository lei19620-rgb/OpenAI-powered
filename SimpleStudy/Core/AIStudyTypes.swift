import Foundation
import SwiftData

enum AIStudyOperation: String, Codable, CaseIterable, Identifiable {
    case explain, practice, feedback
    var id: String { rawValue }
    var title: String {
        switch self { case .explain: "Explain"; case .practice: "Practice"; case .feedback: "Feedback" }
    }
}

struct AIStudySource: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var title: String = "Text input"
    var workspaceID: UUID?
    var assetID: UUID?
    var page: Int?
    var contentHash: String?
    var operation: AIStudyOperation = .explain
}

struct AIStudySection: Codable, Equatable {
    let title: String
    let body: String
    let quote: String
}

struct AIPracticeQuestion: Codable, Equatable {
    let type: HomeworkQuestionType
    let prompt: String
    let options: [HomeworkOption]
    let selectedOptionIDs: [String]
    let acceptedTexts: [String]
    let referenceText: String
    let explanation: String
}

struct AIStudyResult: Codable, Equatable {
    let title: String
    let summary: String
    let sections: [AIStudySection]
    let questions: [AIPracticeQuestion]

    func validate(source: String, operation: AIStudyOperation) throws {
        guard !title.isEmpty, title.count <= 200, !summary.isEmpty,
              summary.count <= 6000, sections.count <= 10, questions.count <= 5 else {
            throw AIServiceError.invalidResult
        }
        for section in sections {
            guard !section.title.isEmpty, !section.body.isEmpty, section.body.count <= 8000,
                  section.quote.isEmpty || source.contains(section.quote) else { throw AIServiceError.invalidResult }
        }
        if operation == .practice {
            guard !questions.isEmpty else { throw AIServiceError.invalidResult }
            for question in questions {
                guard !question.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      Set(question.selectedOptionIDs).count == question.selectedOptionIDs.count else {
                    throw AIServiceError.invalidResult
                }
                switch question.type {
                case .singleChoice, .multipleChoice:
                    guard question.acceptedTexts.isEmpty, question.referenceText.isEmpty else { throw AIServiceError.invalidResult }
                case .fillBlank:
                    guard question.options.isEmpty, question.selectedOptionIDs.isEmpty, question.referenceText.isEmpty else { throw AIServiceError.invalidResult }
                case .openResponse:
                    guard question.options.isEmpty, question.selectedOptionIDs.isEmpty, question.acceptedTexts.isEmpty else { throw AIServiceError.invalidResult }
                }
            }
            _ = try homework(id: "validation")
        } else if !questions.isEmpty || sections.isEmpty {
            throw AIServiceError.invalidResult
        }
    }

    func homework(id: String) throws -> HomeworkPackage {
        let package = HomeworkPackage(schemaVersion: 1, id: "ai-\(id)", title: "\(title) · AI Practice",
            questions: questions.enumerated().map { index, item in
                HomeworkQuestion(id: "q\(index + 1)", type: item.type, prompt: item.prompt,
                    options: item.options.isEmpty ? nil : item.options,
                    answer: HomeworkCorrectAnswer(
                        selectedOptionIDs: item.selectedOptionIDs.isEmpty ? nil : item.selectedOptionIDs,
                        acceptedTexts: item.acceptedTexts.isEmpty ? nil : item.acceptedTexts,
                        referenceText: item.referenceText.isEmpty ? nil : item.referenceText),
                    explanation: item.explanation, points: 1, required: true)
            })
        return try HomeworkImporter.decodeAndValidate(JSONCoding.encode(package))
    }

    func markdown(source: AIStudySource, selectedSections: Set<Int>) -> String {
        let location = source.page.map { " · Page \($0)" } ?? ""
        let content = sections.enumerated().filter { selectedSections.contains($0.offset) }
            .map { "### \($0.element.title)\n\n\($0.element.body)" }.joined(separator: "\n\n")
        let quote = source.text.components(separatedBy: .newlines).map { "> \($0)" }.joined(separator: "\n")
        return "## \(title)\n\n> AI-generated. Review for accuracy. · \(source.title)\(location)\n\n\(quote)\n\n\(summary)\n\n\(content)"
    }
}

@Model
final class AIStudyRecord {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var createdAt: Date = Date()
    var title: String = ""
    var sourceData: Data = Data()
    var resultData: Data = Data()
    var state: String = "prepared"
    var model: String = ""
    var serviceHost: String = ""
    var tokenCount: Int = 0
    var teachingRuleVersion: Int = 1
    var appendedNoteID: UUID?
    var homeworkID: UUID?

    init(source: AIStudySource, model: String, serviceHost: String) {
        self.workspaceID = source.workspaceID
        self.sourceData = JSONCoding.encode(source)
        self.title = source.operation.title
        self.model = model
        self.serviceHost = serviceHost
    }
    var source: AIStudySource? { try? JSONCoding.decoder.decode(AIStudySource.self, from: sourceData) }
    var result: AIStudyResult? { try? JSONCoding.decoder.decode(AIStudyResult.self, from: resultData) }
}
