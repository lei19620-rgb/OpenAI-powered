import AVFoundation
import SwiftUI

struct LocalDictionaryLookupView: View {
    @EnvironmentObject private var dictionaryStore: LocalDictionaryStore

    let query: String

    @State private var result: LocalDictionaryLookupResult = .invalidSelection
    @State private var isSearching = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "character.book.closed")
                    .foregroundStyle(AppTheme.accent)
                Text("Offline lookup")
                    .font(.headline)
                Spacer()
                Text(DictionaryTextNormalizer.containsCJK(query) ? "Chinese → English" : "English → Chinese")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if isSearching {
                ProgressView("Searching offline dictionaries…")
                    .font(.subheadline)
            } else {
                ScrollView {
                    LocalDictionaryResultView(result: result, query: query)
                }
            }
        }
        .padding(18)
        .frame(minWidth: 300, idealWidth: 360, maxWidth: 460, alignment: .leading)
        .frame(minHeight: 180, alignment: .top)
        .background(AppTheme.pageBackground)
        .task(id: query) {
            isSearching = true
            let nextResult = await dictionaryStore.lookupAsync(query)
            guard !Task.isCancelled else { return }
            result = nextResult
            isSearching = false
        }
    }
}

struct LocalDictionaryResultView: View {
    let result: LocalDictionaryLookupResult
    let query: String
    @StateObject private var speechService = LocalDictionarySpeechService()

    init(result: LocalDictionaryLookupResult, query: String = "") {
        self.result = result
        self.query = query
    }

    private var isTranslationQuery: Bool {
        DictionaryTextNormalizer.containsCJK(query)
    }

    var body: some View {
        switch result {
        case .invalidSelection:
            DictionaryResultMessage(
                title: "Selection too long",
                message: "Select a word or short phrase to look it up.",
                systemImage: "text.badge.xmark",
                tint: .orange
            )
        case .noMatch:
            DictionaryResultMessage(
                title: "No entry found",
                message: isTranslationQuery
                    ? "No matching Chinese definition was found. Try a shorter or more common meaning."
                    : "This word or phrase is not in your offline dictionaries.",
                systemImage: "book.closed",
                tint: .secondary
            )
        case .matches(let entries):
            LocalDictionaryMatchesView(
                entries: entries,
                isTranslationQuery: isTranslationQuery,
                speechService: speechService
            )
        }
    }
}

private struct LocalDictionaryMatchesView: View {
    let entries: [LocalDictionaryEntry]
    let isTranslationQuery: Bool
    @ObservedObject var speechService: LocalDictionarySpeechService

    private var wordEntries: [LocalDictionaryEntry] {
        entries.filter { !$0.isPhrase }
    }

    private var phraseEntries: [LocalDictionaryEntry] {
        entries.filter(\.isPhrase)
    }

    private var attachedPhrases: [LocalDictionaryPhrase] {
        var seen = Set(phraseEntries.map { DictionaryTextNormalizer.normalize($0.headword) })
        return wordEntries
            .flatMap(\.phrases)
            .filter {
                let key = DictionaryTextNormalizer.normalize($0.expression)
                return seen.insert(key).inserted
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Label(
                    isTranslationQuery ? "Chinese definition matches" : "English entry matches",
                    systemImage: isTranslationQuery ? "arrow.right" : "arrow.left"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                Spacer()
                Text("\(entries.count) results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !wordEntries.isEmpty {
                DictionarySectionHeader(
                    title: "Parts of speech and senses",
                    subtitle: ""
                )
                ForEach(Array(wordEntries.enumerated()), id: \.offset) { _, entry in
                    LocalDictionaryEntryCard(
                        entry: entry,
                        isTranslationQuery: isTranslationQuery,
                        speechService: speechService
                    )
                }
            }

            if !phraseEntries.isEmpty || !attachedPhrases.isEmpty {
                DictionarySectionHeader(
                    title: "Phrases and idioms",
                    subtitle: ""
                )
                ForEach(Array(phraseEntries.enumerated()), id: \.offset) { _, entry in
                    LocalDictionaryEntryPhraseCard(entry: entry)
                }
                ForEach(Array(attachedPhrases.enumerated()), id: \.offset) { _, phrase in
                    LocalDictionaryPhraseCard(phrase: phrase)
                }
            }
        }
    }
}

private struct DictionaryResultMessage: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct LocalDictionaryEntryCard: View {
    let entry: LocalDictionaryEntry
    let isTranslationQuery: Bool
    @ObservedObject var speechService: LocalDictionarySpeechService

    private var senses: [LocalDictionarySense] {
        LocalDictionarySenseParser.senses(for: entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.headword)
                        .font(.title3.bold())
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(isTranslationQuery ? "English entry" : "Entry")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(AppTheme.accent.opacity(0.10), in: Capsule())
                        if !entry.partOfSpeech.isEmpty {
                            Text(LocalDictionarySenseParser.displayPartOfSpeech(entry.partOfSpeech))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 8)
                LocalDictionarySpeechButtons(
                    entry: entry,
                    speechService: speechService
                )
            }

            if !entry.pronunciationUS.isEmpty || !entry.pronunciationUK.isEmpty || !entry.pronunciation.isEmpty {
                HStack(spacing: 12) {
                    if !entry.pronunciationUS.isEmpty {
                        Label(entry.pronunciationUS, systemImage: "waveform")
                            .accessibilityLabel("US pronunciation \(entry.pronunciationUS)")
                    }
                    if !entry.pronunciationUK.isEmpty {
                        Label(entry.pronunciationUK, systemImage: "waveform.path")
                            .accessibilityLabel("UK pronunciation \(entry.pronunciationUK)")
                    }
                    if entry.pronunciationUS.isEmpty && entry.pronunciationUK.isEmpty {
                        Text(entry.pronunciation)
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }

            if !senses.isEmpty {
                DictionarySenseSection(
                    senses: senses,
                    isTranslationQuery: isTranslationQuery
                )
            } else if !entry.definition.isEmpty {
                DictionaryDetailText(
                    title: isTranslationQuery ? "Matching Chinese definitions" : "Chinese definitions",
                    text: entry.definition,
                    tint: AppTheme.accent.opacity(0.09)
                )
            }
            if senses.isEmpty, !entry.englishDefinition.isEmpty {
                DictionaryDetailText(
                    title: "English definition",
                    text: entry.englishDefinition,
                    tint: Color.secondary.opacity(0.08)
                )
            }
            if !entry.example.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Example", systemImage: "text.quote")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("“\(entry.example)”")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
            }
            if !entry.forms.isEmpty {
                DictionaryDetailLine(title: "Word forms", value: entry.forms)
            }
            if !entry.synonyms.isEmpty || !entry.antonyms.isEmpty {
                DictionaryRelatedSection(entry: entry)
            }
            if !entry.tags.isEmpty {
                DictionaryDetailLine(title: "Tags", value: entry.tags)
            }
            if !entry.sourceName.isEmpty {
                Text("Source: \(entry.sourceName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .textSelection(.enabled)
    }
}

private struct DictionarySenseSection: View {
    let senses: [LocalDictionarySense]
    let isTranslationQuery: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                isTranslationQuery ? "Chinese definitions and parts of speech" : "Parts of speech and Chinese definitions",
                systemImage: "list.number"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accent)

            ForEach(Array(senses.enumerated()), id: \.offset) { index, sense in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            if !sense.partOfSpeech.isEmpty {
                                Text(sense.partOfSpeech)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.accent)
                            }
                            if !sense.note.isEmpty {
                                Text(sense.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !sense.translation.isEmpty {
                                Text(sense.translation)
                                    .font(.subheadline.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if !sense.englishDefinition.isEmpty {
                            Text(sense.englishDefinition)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct DictionaryRelatedSection: View {
    let entry: LocalDictionaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Synonyms, antonyms, and related words", systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !entry.synonyms.isEmpty {
                DictionaryWordChips(title: "Synonyms", value: entry.synonyms, tint: AppTheme.accent)
            }
            if !entry.antonyms.isEmpty {
                DictionaryWordChips(title: "Antonyms", value: entry.antonyms, tint: .orange)
            }
        }
    }
}

private struct DictionaryWordChips: View {
    let title: String
    let value: String
    let tint: Color

    private var words: [String] {
        var seen = Set<String>()
        return value
            .split(whereSeparator: { character in
                character == "," || character == "，" || character == ";" || character == "；" || character == "\u{3001}" || character.isNewline
            })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 80), alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(words, id: \.self) { word in
                    Text(word)
                        .font(.caption)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.10), in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct DictionarySectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}

private struct LocalDictionaryEntryPhraseCard: View {
    let entry: LocalDictionaryEntry

    private var isIdiom: Bool {
        let kind = entry.phraseKind.lowercased()
        return kind.contains("idiom") || kind.contains("\u{4e60}\u{60ef}\u{7528}\u{8bed}")
    }

    private var translation: String {
        let parsed = LocalDictionarySenseParser.senses(for: entry)
            .map(\.translation)
            .filter { !$0.isEmpty }
        return parsed.isEmpty ? entry.definition : parsed.joined(separator: "；")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isIdiom ? "quote.bubble" : "text.quote")
                    .foregroundStyle(AppTheme.accent)
                Text(entry.headword)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(isIdiom ? "Idiom" : "Phrase")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.10), in: Capsule())
            }
            if !translation.isEmpty {
                Text(translation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !entry.partOfSpeech.isEmpty {
                Text(LocalDictionarySenseParser.displayPartOfSpeech(entry.partOfSpeech))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        }
        .textSelection(.enabled)
    }
}

private struct LocalDictionaryPhraseCard: View {
    let phrase: LocalDictionaryPhrase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: phrase.isIdiom ? "quote.bubble" : "text.quote")
                    .foregroundStyle(AppTheme.accent)
                Text(phrase.expression)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(phrase.isIdiom ? "Idiom" : "Phrase")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.10), in: Capsule())
            }
            if !phrase.translation.isEmpty {
                Text(phrase.translation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !phrase.partOfSpeech.isEmpty {
                Text(LocalDictionarySenseParser.displayPartOfSpeech(phrase.partOfSpeech))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        }
        .textSelection(.enabled)
    }
}

private struct DictionaryDetailText: View {
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct DictionaryDetailLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }
}

@MainActor
private final class LocalDictionarySpeechService: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.46
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    deinit {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

private struct LocalDictionarySpeechButtons: View {
    let entry: LocalDictionaryEntry
    @ObservedObject var speechService: LocalDictionarySpeechService

    var body: some View {
        HStack(spacing: 4) {
            if !entry.pronunciationUS.isEmpty || !entry.pronunciationUK.isEmpty {
                if !entry.pronunciationUS.isEmpty {
                    Button {
                        speechService.speak(entry.headword, language: "en-US")
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .accessibilityLabel("Play US pronunciation")
                }
                if !entry.pronunciationUK.isEmpty {
                    Button {
                        speechService.speak(entry.headword, language: "en-GB")
                    } label: {
                        Image(systemName: "speaker.wave.2")
                    }
                    .accessibilityLabel("Play UK pronunciation")
                }
            } else {
                Button {
                    speechService.speak(entry.headword, language: "en-US")
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .accessibilityLabel("Play pronunciation")
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(AppTheme.accent)
    }
}

struct LocalDictionaryLookupButton: View {
    let query: String

    @State private var isPresented = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Look up", systemImage: "character.book.closed")
        }
        .disabled(trimmedQuery.isEmpty)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            LocalDictionaryLookupView(query: trimmedQuery)
        }
    }
}
