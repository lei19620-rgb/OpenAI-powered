import XCTest
import SwiftData
@testable import SimpleStudy

@MainActor
final class AIStudyTests: XCTestCase {
    private let source = AIStudySource(text: "I am happy.")
    private var explanation: AIStudyResult {
        .init(title: "Expressing a state", summary: "I am happy.", sections: [
            .init(title: "Sentence structure", body: "I is the subject, am is a linking verb, and happy is the subject complement.", quote: "I am happy.")
        ], questions: [])
    }

    private func envelope(_ result: AIStudyResult, status: String = "completed") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": status, "usage": ["total_tokens": 42],
            "output": [["type": "message", "content": [["type": "output_text", "text": String(data: JSONCoding.encode(result), encoding: .utf8)!]]]]])
    }

    func testOfficialEndpointAndStoreFalse() throws {
        let config = AIServiceConfiguration(baseURL: "https://api.openai.com/v1", model: "test-model")
        let request = try AIStudyService.request(source: source, configuration: config, key: "test-only")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertNil(body["tools"])
        XCTAssertNil(body["previous_response_id"])
        XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains("test-only"))
    }

    func testUnsafeEndpointsRejected() {
        for endpoint in ["http://api.openai.com/v1", "https://user:pass@example.com", "https://example.com?key=a", "https://example.com/#key"] {
            XCTAssertThrowsError(try AIServiceConfiguration(baseURL: endpoint, model: "test").endpoint())
        }
    }

    func testConfigurationRequiresExplicitModel() {
        XCTAssertThrowsError(try AIServiceConfiguration(baseURL: "https://api.openai.com/v1", model: " ").endpoint())
    }

    func testInputLimitAndMissingKey() {
        let config = AIServiceConfiguration(baseURL: "https://api.openai.com/v1", model: "test")
        XCTAssertThrowsError(try AIStudyService.request(source: source, configuration: config, key: ""))
        XCTAssertThrowsError(try AIStudyService.request(source: AIStudySource(text: String(repeating: "a", count: 6001)), configuration: config, key: "test"))
    }

    func testValidResponseDecoded() throws {
        let (result, usage) = try AIStudyService.decode(envelope(explanation), source: source)
        XCTAssertEqual(result, explanation)
        XCTAssertEqual(usage, 42)
    }

    func testIncompleteResponseNotAccepted() throws {
        XCTAssertThrowsError(try AIStudyService.decode(envelope(explanation, status: "incomplete"), source: source))
    }

    func testRefusalNotAccepted() throws {
        let data = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
            ["type": "message", "content": [["type": "refusal", "refusal": "No"]]]]])
        XCTAssertThrowsError(try AIStudyService.decode(data, source: source))
    }

    func testFabricatedQuoteRejected() {
        XCTAssertThrowsError(try explanation.validate(source: "Another sentence.", operation: .explain))
    }

    func testPracticeRequiresQuestions() {
        XCTAssertThrowsError(try explanation.validate(source: source.text, operation: .practice))
    }

    func testPracticeConvertedToExistingHomeworkFormat() throws {
        let answer = AIStudyResult(title: "Linking verbs", summary: "Practice subject complements", sections: [], questions: [
            AIPracticeQuestion(type: .singleChoice, prompt: "I ___ happy.", options: [.init(id: "a", text: "am"), .init(id: "b", text: "is")], selectedOptionIDs: ["a"], acceptedTexts: [], referenceText: "", explanation: "Use am with I.")])
        try answer.validate(source: source.text, operation: .practice)
        let package = try answer.homework(id: "test")
        XCTAssertEqual(package.id, "ai-test")
        XCTAssertEqual(package.questions.first?.answer.selectedOptionIDs, ["a"])
    }

    func testUnknownCorrectOptionRejected() {
        let invalid = AIStudyResult(title: "Practice", summary: "Practice", sections: [], questions: [
            AIPracticeQuestion(type: .singleChoice, prompt: "Question", options: [.init(id: "a", text: "A"), .init(id: "b", text: "B")], selectedOptionIDs: ["missing"], acceptedTexts: [], referenceText: "", explanation: "Explanation")])
        XCTAssertThrowsError(try invalid.homework(id: "test"))
    }

    func testExportOnlyIncludesSelectedSectionsAndSource() {
        let markdown = explanation.markdown(source: source, selectedSections: [])
        XCTAssertTrue(markdown.contains("I am happy."))
        XCTAssertTrue(markdown.contains("AI-generated"))
        XCTAssertFalse(markdown.contains("I is the subject"))
    }

    func testRecordPersistenceAndNoCredentials() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.mainContext
        let item = AIStudyRecord(source: source, model: "test", serviceHost: "https://api.openai.com/v1")
        item.resultData = JSONCoding.encode(explanation)
        context.insert(item)
        try context.save()
        let saved = try context.fetch(FetchDescriptor<AIStudyRecord>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.result, explanation)
        XCTAssertEqual(saved.first?.source, source)
    }
}
