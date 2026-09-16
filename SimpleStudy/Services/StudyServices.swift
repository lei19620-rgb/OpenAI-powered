import Foundation
import PDFKit
import UIKit
import Vision
import SwiftData

enum LessonSequenceResolver {
    private static let patterns = [
        #"(?i)\bday[\s_-]*([0-9]{1,4})\b"#,
        #"(?i)\blesson[\s_-]*([0-9]{1,4})\b"#,
        #"(?i)\bunit[\s_-]*([0-9]{1,4})\b"#,
        #"\u7b2c\s*([0-9]{1,4})\s*[\u8bfe\u8bb2\u5929]"#
    ]

    static func infer(fileName: String, firstPageText: String?, fallback: Int) -> LessonSequenceInference {
        if let match = firstSequence(in: fileName) {
            return .init(sequence: match, confidence: 0.98, evidence: "Lesson order found in the filename")
        }
        if let text = firstPageText, let match = firstSequence(in: text) {
            return .init(sequence: match, confidence: 0.82, evidence: "Lesson order found on the first PDF page")
        }
        return .init(sequence: fallback, confidence: 0.42, evidence: "Inferred from progress and import order")
    }

    private static func firstSequence(in text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text),
                  let value = Int(text[valueRange]), value > 0 else { continue }
            return value
        }
        return nil
    }
}

struct PreparedStudyMaterial: Sendable {
    let fileName: String
    let data: Data
    let sequence: Int
    let confidence: Double
    let evidence: String
    let questions: [String]
}

enum StudyMaterialImporter {
    static func prepare(urls: [URL], startingSequence: Int) async throws -> [PreparedStudyMaterial] {
        let worker = Task.detached(priority: .userInitiated) {
            var materials: [PreparedStudyMaterial] = []
            var totalBytes = 0
            for (offset, url) in urls.enumerated() {
                try Task.checkCancellation()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 50_000_000, totalBytes + size <= 200_000_000 else { throw StudyMaterialImportError.tooLarge }
                let data = try Data(contentsOf: url)
                totalBytes += data.count
                guard data.count <= 50_000_000, totalBytes <= 200_000_000 else { throw StudyMaterialImportError.tooLarge }
                guard let document = PDFDocument(data: data), !document.isLocked,
                      document.pageCount > 0, document.pageCount <= 1_000 else {
                    throw StudyMaterialImportError.invalidFile(url.lastPathComponent)
                }
                let inference = LessonSequenceResolver.infer(fileName: url.lastPathComponent,
                    firstPageText: document.page(at: 0)?.string, fallback: startingSequence + offset)
                var text = ""
                for page in 0..<document.pageCount {
                    try Task.checkCancellation()
                    text += (document.page(at: page)?.string ?? "") + "\n"
                    guard text.utf8.count <= 10_000_000 else { throw StudyMaterialImportError.tooLarge }
                }
                materials.append(PreparedStudyMaterial(fileName: url.lastPathComponent, data: data,
                    sequence: inference.sequence, confidence: inference.confidence, evidence: inference.evidence,
                    questions: PDFTextService.extractQuestions(from: text)))
            }
            return materials
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    @MainActor
    static func commit(_ materials: [PreparedStudyMaterial], course: CourseRecord, context: ModelContext) throws {
        var workspaces = try context.fetch(FetchDescriptor<StudyWorkspaceRecord>()).filter { $0.courseID == course.id }
        var assets = try context.fetch(FetchDescriptor<StudyAssetRecord>())
        do {
            for material in materials {
                let workspace = workspaces.first { $0.sequence == material.sequence }
                    ?? StudyWorkspaceRecord(courseID: course.id, sequence: material.sequence,
                                            title: "\(course.title) · Day \(material.sequence)")
                if workspace.modelContext == nil {
                    context.insert(workspace)
                    workspaces.append(workspace)
                }
                guard !assets.contains(where: { $0.workspaceID == workspace.id && $0.originalFileName == material.fileName && $0.fileData == material.data }) else { continue }
                let asset = StudyAssetRecord(workspaceID: workspace.id,
                    displayName: (material.fileName as NSString).deletingPathExtension,
                    originalFileName: material.fileName, fileData: material.data)
                asset.resolvedSequence = material.sequence
                asset.inferenceConfidence = material.confidence
                asset.inferenceEvidence = material.evidence
                asset.extractedQuestions = material.questions
                context.insert(asset)
                assets.append(asset)
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}

enum StudyMaterialImportError: LocalizedError {
    case tooLarge
    case invalidFile(String)
    var errorDescription: String? {
        switch self {
        case .tooLarge: "Each PDF may contain up to 1,000 pages and 50 MB. Import at most 200 MB per batch."
        case .invalidFile(let name): "Unable to read “\(name)”. Use a valid, unencrypted PDF. No files were imported."
        }
    }
}

@MainActor
enum CourseProgressService {
    static func complete(_ workspace: StudyWorkspaceRecord, context: ModelContext) throws {
        let courses = try context.fetch(FetchDescriptor<CourseRecord>())
        let workspaces = try context.fetch(FetchDescriptor<StudyWorkspaceRecord>())
        workspace.isCompleted = true
        workspace.completedAt = workspace.completedAt ?? Date()
        if let course = courses.first(where: { $0.id == workspace.courseID }) {
            let completed = Set(workspaces.filter { $0.courseID == course.id && $0.isCompleted }.map(\.sequence))
            while completed.contains(course.currentSequence) { course.currentSequence += 1 }
            course.updatedAt = Date()
        }
    }
}

enum PDFTextService {
    static func firstPageText(data: Data) -> String? {
        PDFDocument(data: data)?.page(at: 0)?.string
    }

    static func embeddedText(data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
    }

    static func extractQuestions(from text: String) -> [String] {
        let numbered = try? NSRegularExpression(pattern: #"^\s*(?:[0-9]+[.)、]|[A-Z][.)])\s+.+"#, options: .anchorsMatchLines)
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if line.hasSuffix("?") || line.hasSuffix("？") { return true }
                let range = NSRange(line.startIndex..., in: line)
                return numbered?.firstMatch(in: line, range: range) != nil
            }
    }

    static func recognize(data: Data, progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        let worker = Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(data: data) else { throw PDFProcessingError.invalidPDF }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index), let cgImage = render(page: page) else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US", "zh-Hans"]
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try handler.perform([request])
                let text = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                pages.append(text)
                progress(Double(index + 1) / Double(max(document.pageCount, 1)))
            }
            return pages.joined(separator: "\n\n")
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2, 1800 / max(bounds.width, bounds.height))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
        return image.cgImage
    }
}

enum PDFProcessingError: LocalizedError {
    case invalidPDF

    var errorDescription: String? { "Unable to read this PDF" }
}

enum NoteRenderingService {
    static func render(
        template: NoteTemplateRecord,
        courseTitle: String,
        day: Int,
        materialName: String?
    ) -> String {
        let now = Date()
        let dateParts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let dateText = "\(dateParts.year ?? 0)/\(dateParts.month ?? 0)/\(dateParts.day ?? 0)"
        let values = [
            "{{course}}": courseTitle,
            "{{day}}": String(day),
            "{{date}}": dateText,
            "{{material}}": materialName ?? "Current material",
            "{{reviewDate}}": Calendar.current.date(byAdding: .day, value: 1, to: now)?
                .formatted(date: .numeric, time: .omitted) ?? ""
        ]

        var hasDocumentTitle = false
        return template.blocks.map { block in
            var title = block.title
            for (key, value) in values { title = title.replacingOccurrences(of: key, with: value) }
            return switch block.kind {
            case .heading:
                if hasDocumentTitle {
                    "## \(title)\n"
                } else {
                    {
                        hasDocumentTitle = true
                        return "# \(title)\n"
                    }()
                }
            case .checklist: "## \(title)\n- [ ] \(block.placeholder)\n"
            case .quote:
                block.placeholder.isEmpty
                    ? "> **\(title)**\n>\n"
                    : "> **\(title)**\n>\n> \(block.placeholder)\n"
            case .divider: "---\n"
            case .reviewQuestion: "## \(title)\n\(block.placeholder)\n"
            case .table: "## \(title)\n| Content | Notes |\n| --- | --- |\n|  |  |\n"
            case .attachment: "## \(title)\n[Attachment]\n"
            case .handwriting: "## \(title)\n[Handwriting]\n"
            case .richText: "## \(title)\n\(block.placeholder)\n"
            }
        }.joined(separator: "\n")
    }
}
