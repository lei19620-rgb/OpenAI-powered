import Foundation

struct NoteTemplatePackage: Codable, Equatable {
    let schemaVersion: Int
    let name: String
    let details: String
    let sourceVersion: Int
    let blocks: [NoteBlock]
}

enum NoteTemplateImportError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidJSON(String)
    case unsupportedVersion(Int)
    case invalidName
    case detailsTooLong
    case noBlocks
    case tooManyBlocks
    case duplicateBlockID
    case invalidBlock(index: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "Template files must not exceed 1 MB"
        case .invalidJSON(let reason): "Invalid template JSON: \(reason)"
        case .unsupportedVersion(let version): "Unsupported schema version \(version); only version 1 is supported"
        case .invalidName: "Template names must contain 1–80 characters"
        case .detailsTooLong: "Template descriptions must not exceed 1,000 characters"
        case .noBlocks: "A template needs at least one block"
        case .tooManyBlocks: "A template supports up to 100 blocks"
        case .duplicateBlockID: "Block IDs must be unique"
        case .invalidBlock(let index, let reason): "Block \(index + 1): \(reason)"
        }
    }
}

enum NoteTemplatePackageService {
    static let maximumFileSize = 1_000_000

    static func package(for template: NoteTemplateRecord) -> NoteTemplatePackage {
        NoteTemplatePackage(
            schemaVersion: 1,
            name: template.name,
            details: template.details,
            sourceVersion: template.version,
            blocks: template.blocks
        )
    }

    static func exportData(for template: NoteTemplateRecord) throws -> Data {
        try prettyEncoder.encode(package(for: template))
    }

    static func decodeAndValidate(_ data: Data) throws -> NoteTemplatePackage {
        guard data.count <= maximumFileSize else { throw NoteTemplateImportError.fileTooLarge }

        let package: NoteTemplatePackage
        do {
            package = try JSONCoding.decoder.decode(NoteTemplatePackage.self, from: data)
        } catch {
            throw NoteTemplateImportError.invalidJSON(error.localizedDescription)
        }

        guard package.schemaVersion == 1 else {
            throw NoteTemplateImportError.unsupportedVersion(package.schemaVersion)
        }
        let trimmedName = package.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, package.name.count <= 80 else {
            throw NoteTemplateImportError.invalidName
        }
        guard package.details.count <= 1_000 else { throw NoteTemplateImportError.detailsTooLong }
        guard !package.blocks.isEmpty else { throw NoteTemplateImportError.noBlocks }
        guard package.blocks.count <= 100 else { throw NoteTemplateImportError.tooManyBlocks }
        guard Set(package.blocks.map(\.id)).count == package.blocks.count else {
            throw NoteTemplateImportError.duplicateBlockID
        }

        for (index, block) in package.blocks.enumerated() {
            guard !block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NoteTemplateImportError.invalidBlock(index: index, reason: "Title is required")
            }
            guard block.title.count <= 120 else {
                throw NoteTemplateImportError.invalidBlock(index: index, reason: "Titles must not exceed 120 characters")
            }
            guard block.placeholder.count <= 1_000 else {
                throw NoteTemplateImportError.invalidBlock(index: index, reason: "Hints must not exceed 1,000 characters")
            }
        }
        return package
    }

    static var examplePackage: NoteTemplatePackage {
        NoteTemplatePackage(
            schemaVersion: 1,
            name: "Sentence Study",
            details: "Daily Markdown notes with the day and date filled in when created",
            sourceVersion: 1,
            blocks: [
                NoteBlock(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                    kind: .heading,
                    title: "📝Day {{day}}   📆{{date}}"
                ),
                NoteBlock(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                    kind: .quote,
                    title: "• 📚Sentence"
                ),
                NoteBlock(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
                    kind: .quote,
                    title: "• 📔Words and Expressions"
                ),
                NoteBlock(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
                    kind: .quote,
                    title: "• 📝Grammar"
                ),
                NoteBlock(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
                    kind: .quote,
                    title: "• ✅Output"
                )
            ]
        )
    }

    static func exampleData() throws -> Data {
        try prettyEncoder.encode(examplePackage)
    }

    private static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}
