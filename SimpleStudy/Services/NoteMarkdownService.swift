import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum NoteMarkdownError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidUTF8
    case containsNullCharacter

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "Markdown files must not exceed 2 MB"
        case .invalidUTF8: "Markdown files must use UTF-8 encoding"
        case .containsNullCharacter: "Markdown file contains unsupported null characters"
        }
    }
}

enum MarkdownFormat: String, CaseIterable, Identifiable {
    case heading
    case bold
    case italic
    case checklist
    case bullet
    case quote
    case inlineCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heading: "Title"
        case .bold: "Bold"
        case .italic: "Italic"
        case .checklist: "Task"
        case .bullet: "List"
        case .quote: "Quote"
        case .inlineCode: "Code"
        }
    }

    var systemImage: String {
        switch self {
        case .heading: "textformat.size"
        case .bold: "bold"
        case .italic: "italic"
        case .checklist: "checklist"
        case .bullet: "list.bullet"
        case .quote: "text.quote"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct MarkdownEditResult: Equatable {
    let content: String
    let selectedCharacterRange: Range<Int>
}

enum NoteMarkdownService {
    static let maximumFileSize = 2_000_000

    static let exampleContent = """
    # 📝Day 2   📆2026/8/25

    > **• 📚Sentence**
    >

    > **• 📔Words and Expressions**
    >

    > **• 📝Grammar**
    >

    > **• ✅Output**
    >
    """

    static func decode(_ data: Data) throws -> String {
        guard data.count <= maximumFileSize else { throw NoteMarkdownError.fileTooLarge }
        var normalizedData = data
        if normalizedData.starts(with: [0xEF, 0xBB, 0xBF]) {
            normalizedData.removeFirst(3)
        }
        guard let text = String(data: normalizedData, encoding: .utf8) else {
            throw NoteMarkdownError.invalidUTF8
        }
        guard !text.contains("\0") else { throw NoteMarkdownError.containsNullCharacter }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func apply(
        _ format: MarkdownFormat,
        to content: String,
        selectedCharacterRange: Range<Int>?
    ) -> MarkdownEditResult {
        let count = content.count
        let requested = selectedCharacterRange ?? count..<count
        let lower = min(max(0, requested.lowerBound), count)
        let upper = min(max(lower, requested.upperBound), count)
        let lowerIndex = content.index(content.startIndex, offsetBy: lower)
        let upperIndex = content.index(content.startIndex, offsetBy: upper)
        let selected = String(content[lowerIndex..<upperIndex])

        let replacement: String
        let selectedStart: Int
        let selectedLength: Int
        switch format {
        case .bold:
            let value = selected.isEmpty ? "Bold text" : selected
            replacement = "**\(value)**"
            selectedStart = 2
            selectedLength = value.count
        case .italic:
            let value = selected.isEmpty ? "Italic text" : selected
            replacement = "_\(value)_"
            selectedStart = 1
            selectedLength = value.count
        case .inlineCode:
            let value = selected.isEmpty ? "Code" : selected
            replacement = "`\(value)`"
            selectedStart = 1
            selectedLength = value.count
        case .heading, .checklist, .bullet, .quote:
            let prefix = switch format {
            case .heading: "## "
            case .checklist: "- [ ] "
            case .bullet: "- "
            case .quote: "> "
            default: ""
            }
            let placeholder = switch format {
            case .heading: "Title"
            case .checklist: "Task to complete"
            case .bullet: "List item"
            case .quote: "Quoted text"
            default: ""
            }
            let value = selected.isEmpty ? placeholder : selected
            let prefixed = value.replacingOccurrences(of: "\n", with: "\n\(prefix)")
            let needsLeadingBreak = lower > 0 && content[content.index(before: lowerIndex)] != "\n"
            replacement = (needsLeadingBreak ? "\n" : "") + prefix + prefixed
            selectedStart = (needsLeadingBreak ? 1 : 0) + prefix.count
            selectedLength = prefixed.count
        }

        var updated = content
        updated.replaceSubrange(lowerIndex..<upperIndex, with: replacement)
        let start = lower + selectedStart
        return MarkdownEditResult(
            content: updated,
            selectedCharacterRange: start..<(start + selectedLength)
        )
    }

    static func safeFileName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = title
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "StudyAI-Note" : cleaned
    }
}

struct MarkdownNoteDocument: FileDocument {
    static var readableContentTypes: [UTType] { [ProductFileType.markdown, .plainText] }

    var content: String

    init(content: String = "") {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        content = try NoteMarkdownService.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}

struct MarkdownPreviewView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .textSelection(.enabled)
        .background(.background)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(level == 1 ? .title.bold() : level == 2 ? .title2.bold() : .headline)
                .padding(.top, level == 1 ? 6 : 2)
        case .checklist(let checked, let text):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? .green : .secondary)
                inlineText(text)
            }
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                inlineText(text)
            }
        case .quote(let text):
            inlineText(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(AppTheme.accent).frame(width: 3)
                }
        case .divider:
            Divider()
        case .code(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        case .table(let text):
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text):
            inlineText(text)
        case .spacing:
            Color.clear.frame(height: 2)
        }
    }

    private func inlineText(_ value: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(value)
    }

    private var blocks: [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var codeLines: [String] = []
        var isInCodeBlock = false

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if isInCodeBlock {
                    result.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                }
                isInCodeBlock.toggle()
                continue
            }
            if isInCodeBlock {
                codeLines.append(line)
                continue
            }
            if line == "---" || line == "***" {
                result.append(.divider)
            } else if line.hasPrefix("### ") {
                result.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                result.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                result.append(.heading(level: 1, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                result.append(.checklist(checked: true, text: String(line.dropFirst(6))))
            } else if line.hasPrefix("- [ ] ") {
                result.append(.checklist(checked: false, text: String(line.dropFirst(6))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result.append(.bullet(String(line.dropFirst(2))))
            } else if line == ">" {
                result.append(.spacing)
            } else if line.hasPrefix("> ") {
                result.append(.quote(String(line.dropFirst(2))))
            } else if line.hasPrefix("|") {
                result.append(.table(line))
            } else if line.isEmpty {
                result.append(.spacing)
            } else {
                result.append(.paragraph(line))
            }
        }
        if !codeLines.isEmpty { result.append(.code(codeLines.joined(separator: "\n"))) }
        return result
    }
}

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case checklist(checked: Bool, text: String)
    case bullet(String)
    case quote(String)
    case divider
    case code(String)
    case table(String)
    case paragraph(String)
    case spacing
}
