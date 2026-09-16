import Foundation
import Security

enum AIServiceError: LocalizedError {
    case configuration, missingKey, invalidResult, refused, incomplete, http(Int), oversized, keychain
    var errorDescription: String? {
        switch self {
        case .configuration: "Set an HTTPS endpoint and model in AI settings. The URL must not contain credentials, query parameters, or a fragment."
        case .missingKey: "Add an API key in AI settings first."
        case .invalidResult: "The response did not pass validation and was not saved as a valid explanation or assignment."
        case .refused: "The service could not process this content. Check or shorten the selection."
        case .incomplete: "The response was incomplete and was not saved as a valid result. Try a shorter passage."
        case .http(let status): status == 401 ? "Authentication failed. Check your API key." : status == 429 ? "The service quota or rate limit was reached. Check your account before trying again." : "Service unavailable (\(status)). Check the endpoint, model, and connection."
        case .oversized: "The content is too long. Select a shorter passage."
        case .keychain: "Keychain access failed. Unlock this device and try again."
        }
    }
}

enum AIKeychain {
    private static let service = "app.studyai.personal.credentials"
    static func read(host: String) throws -> String {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: host,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        query[kSecAttrSynchronizable as String] = false
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { throw AIServiceError.keychain }
        return value
    }
    static func save(_ key: String, host: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: host,
            kSecAttrSynchronizable as String: false]
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AIServiceError.keychain }
            return
        }
        let attrs: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
                throw AIServiceError.keychain
            }
        } else if status != errSecSuccess { throw AIServiceError.keychain }
    }
}

struct AIServiceConfiguration: Equatable {
    var baseURL: String
    var model: String
    var outputLimit: Int = 4000
    static var saved: Self {
        .init(baseURL: UserDefaults.standard.string(forKey: "ai.baseURL") ?? "https://api.openai.com/v1",
              model: UserDefaults.standard.string(forKey: "ai.model") ?? "",
              outputLimit: UserDefaults.standard.object(forKey: "ai.outputLimit") as? Int ?? 4000)
    }
    func endpoint() throws -> URL {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1000...8000).contains(outputLimit) else { throw AIServiceError.configuration }
        return url.appendingPathComponent("responses")
    }
    var credentialScope: String { baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    func save() throws {
        _ = try endpoint()
        UserDefaults.standard.set(baseURL, forKey: "ai.baseURL")
        UserDefaults.standard.set(model, forKey: "ai.model")
        UserDefaults.standard.set(outputLimit, forKey: "ai.outputLimit")
    }
}

private final class AINoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum AIStudyService {
    static let maximumInputCharacters = 6000
    static func request(source: AIStudySource, configuration: AIServiceConfiguration, key: String) throws -> URLRequest {
        guard !key.isEmpty else { throw AIServiceError.missingKey }
        guard !source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.text.count <= maximumInputCharacters else { throw AIServiceError.oversized }
        var request = URLRequest(url: try configuration.endpoint())
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model, "store": false, "max_output_tokens": configuration.outputLimit,
            "instructions": AITeachingRules.instructions(for: source.operation),
            "input": [["role": "user", "content": [["type": "input_text", "text": source.text]]]],
            "text": ["format": ["type": "json_schema", "name": "study_result", "strict": true, "schema": schema]]
        ])
        return request
    }

    static func generate(source: AIStudySource, configuration: AIServiceConfiguration, key: String) async throws -> (AIStudyResult, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 150
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: AINoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request(source: source, configuration: configuration, key: key))
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResult }
        guard (200...299).contains(http.statusCode) else { throw AIServiceError.http(http.statusCode) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2_000_000 else { throw AIServiceError.oversized }
            data.append(byte)
        }
        return try decode(data, source: source)
    }

    static func decode(_ data: Data, source: AIStudySource) throws -> (AIStudyResult, Int) {
        guard data.count <= 2_000_000,
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["status"] as? String == "completed",
              let output = envelope["output"] as? [[String: Any]] else { throw AIServiceError.incomplete }
        let content = output.filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
        guard !content.contains(where: { $0["type"] as? String == "refusal" }) else { throw AIServiceError.refused }
        let text = content.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined()
        guard let result = try? JSONDecoder().decode(AIStudyResult.self, from: Data(text.utf8)) else { throw AIServiceError.invalidResult }
        try result.validate(source: source.text, operation: source.operation)
        let count = (envelope["usage"] as? [String: Any])?["total_tokens"] as? Int ?? 0
        return (result, max(0, count))
    }

    static var schema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        func array(_ item: [String: Any]) -> [String: Any] { ["type": "array", "items": item] }
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
        }
        return object([
            "title": string, "summary": string,
            "sections": array(object(["title": string, "body": string, "quote": string])),
            "questions": array(object([
                "type": ["type": "string", "enum": HomeworkQuestionType.allCases.map(\.rawValue)],
                "prompt": string, "options": array(object(["id": string, "text": string])),
                "selectedOptionIDs": array(string), "acceptedTexts": array(string),
                "referenceText": string, "explanation": string
            ]))
        ])
    }
}
