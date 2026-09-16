import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum VocabularyRoute: Hashable {
    case courseware(UUID)
    case review(coursewareID: UUID?, unitID: UUID?, mode: VocabularySessionMode = .all)
}

private struct VocabularyImportDraft: Identifiable {
    let id = UUID()
    let package: VocabularyCoursewarePackage
    let sourceFileName: String
}

struct VocabularyView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyCoursewareRecord.updatedAt, order: .reverse)
    private var coursewares: [VocabularyCoursewareRecord]
    @Query private var units: [VocabularyUnitRecord]
    @Query private var items: [VocabularyItemRecord]

    @State private var path: [VocabularyRoute] = []
    @State private var showsImporter = false
    @State private var importDraft: VocabularyImportDraft?
    @State private var importError: String?
    @State private var lastHandledVocabularyRequest = 0

    private var activeItems: [VocabularyItemRecord] {
        items.filter(\.isActive)
    }

    private var newCount: Int {
        activeItems.filter { $0.firstLearnedAt == nil }.count
    }

    private var dueCount: Int {
        let now = Date()
        return activeItems.filter { $0.firstLearnedAt != nil && ($0.dueAt ?? .distantFuture) <= now }.count
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    LocalDictionarySearchCard()

                    if !coursewares.isEmpty {
                        HStack(spacing: 14) {
                            Button {
                                path.append(.review(coursewareID: nil, unitID: nil, mode: .newWords))
                            } label: {
                                VocabularyMetric(title: "Learn new words", value: "\(newCount)", tint: AppTheme.accent)
                            }
                            .disabled(newCount == 0)
                            Button {
                                path.append(.review(coursewareID: nil, unitID: nil, mode: .review))
                            } label: {
                                VocabularyMetric(title: "Due for review", value: "\(dueCount)", tint: .green)
                            }
                            .disabled(dueCount == 0)
                        }
                        .buttonStyle(.plain)
                    }

                    if coursewares.isEmpty {
                        ContentUnavailableView {
                            Label("No word collections yet", systemImage: "character.book.closed")
                        } description: {
                            Text("Import a grouped word list and study one unit at a time.")
                        } actions: {
                            Button("Import word collection") { showsImporter = true }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(minHeight: 260)
                    } else {
                        SectionCard(title: "Your word collections", systemImage: "books.vertical") {
                            ForEach(coursewares) { courseware in
                                Button {
                                    path.append(.courseware(courseware.id))
                                } label: {
                                    VocabularyCoursewareRow(
                                        courseware: courseware,
                                        units: units.filter { $0.coursewareID == courseware.id && $0.isActive },
                                        items: activeItems.filter { $0.coursewareID == courseware.id }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle("Words")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    NavigationLink {
                        VocabularyFormatView()
                    } label: {
                        Image(systemName: "curlybraces")
                    }
                    .accessibilityLabel("View word collection format")

                    Button { showsImporter = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationDestination(for: VocabularyRoute.self) { route in
                switch route {
                case .courseware(let id):
                    if let courseware = coursewares.first(where: { $0.id == id }) {
                        VocabularyCoursewareView(courseware: courseware)
                    } else {
                        ContentUnavailableView("Word collection not found", systemImage: "exclamationmark.triangle")
                    }
                case .review(let coursewareID, let unitID, let mode):
                    VocabularyReviewView(coursewareID: coursewareID, unitID: unitID, mode: mode)
                }
            }
            .fileImporter(
                isPresented: $showsImporter,
                allowedContentTypes: [.json],
                onCompletion: importCourseware
            )
            .sheet(item: $importDraft) { draft in
                VocabularyImportPreviewView(
                    package: draft.package,
                    sourceFileName: draft.sourceFileName
                )
            }
            .alert("Word collection import failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .onChange(of: router.vocabularyRequest) { _, request in
                handleVocabularyRequest(request)
            }
            .onAppear {
                handleVocabularyRequest(router.vocabularyRequest)
            }
        }
    }

    private func handleVocabularyRequest(_ request: Int) {
        guard request > 0, request != lastHandledVocabularyRequest else { return }
        lastHandledVocabularyRequest = request
        path = [.review(
            coursewareID: router.requestedVocabularyCoursewareID,
            unitID: router.requestedVocabularyUnitID
        )]
        router.requestedVocabularyCoursewareID = nil
        router.requestedVocabularyUnitID = nil
    }

    private func importCourseware(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > VocabularyCoursewareService.maximumFileSize {
                throw VocabularyImportError.fileTooLarge
            }
            let data = try Data(contentsOf: url)
            let package = try VocabularyCoursewareService.decodeAndValidate(data)
            importDraft = VocabularyImportDraft(package: package, sourceFileName: url.lastPathComponent)
        } catch {
            importError = error.localizedDescription
        }
    }
}


private struct VocabularyMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 18)
    }
}

private struct VocabularyCoursewareRow: View {
    let courseware: VocabularyCoursewareRecord
    let units: [VocabularyUnitRecord]
    let items: [VocabularyItemRecord]

    private var completedUnits: Int { units.filter { $0.completedAt != nil }.count }
    private var learnedItems: Int { items.filter { $0.firstLearnedAt != nil }.count }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: courseware.completedAt == nil ? "book.closed" : "checkmark.seal.fill")
                .font(.title3)
                .appIconBadge(
                    tint: courseware.completedAt == nil ? AppTheme.accent : .green,
                    size: 38,
                    radius: 11
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(courseware.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(completedUnits)/\(units.count) units complete · \(learnedItems)/\(items.count) words studied")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

private struct LocalDictionarySearchCard: View {
    @EnvironmentObject private var dictionaryStore: LocalDictionaryStore
    @State private var query = ""
    @State private var result: LocalDictionaryLookupResult?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = 0
    @FocusState private var isFocused: Bool

    private var normalizedQuery: String {
        DictionaryTextNormalizer.normalize(query)
    }

    private var directionTitle: String {
        guard !normalizedQuery.isEmpty else { return "English ↔ Chinese" }
        return DictionaryTextNormalizer.containsCJK(normalizedQuery)
            ? "Chinese meaning → English entry"
            : "English entry → Chinese meaning"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "character.book.closed.fill")
                    .font(.title3)
                    .appIconBadge(size: 40, radius: 12)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Look it up. Make it stick.")
                        .font(.title2.weight(.semibold))
                    Text("English–Chinese · Offline dictionary")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                NavigationLink {
                    LocalDictionaryManagementView()
                } label: {
                    Image(systemName: "books.vertical").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Manage offline dictionaries")
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search a word or Chinese meaning", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isFocused)
                    .onSubmit { search() }
                if !query.isEmpty {
                    Button {
                        query = ""
                        result = nil
                        isFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
                Button {
                    search()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .disabled(normalizedQuery.isEmpty)
                .accessibilityLabel("Look up")
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 16)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? AppTheme.accent : Color.secondary.opacity(0.18), lineWidth: isFocused ? 2 : 1)
            }

            if !normalizedQuery.isEmpty || !dictionaryStore.hasEntries {
              HStack(spacing: 8) {
                Label(directionTitle, systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !dictionaryStore.hasEntries {
                    Text("No dictionary installed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
              }
            }

            if let result, !isSearching {
                LocalDictionaryResultView(result: result, query: normalizedQuery)
            }

        }
        .appCard(padding: 18, radius: AppTheme.heroRadius)
        .onChange(of: query) { _, _ in
            result = nil
            searchGeneration += 1
            searchTask?.cancel()
            searchTask = nil
            isSearching = false
        }
        .onDisappear {
            searchGeneration += 1
            searchTask?.cancel()
            searchTask = nil
            isSearching = false
        }
    }

    private func search() {
        let querySnapshot = normalizedQuery
        guard !querySnapshot.isEmpty else { return }
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        searchTask = Task { @MainActor in
            let nextResult = await dictionaryStore.lookupAsync(querySnapshot)
            guard !Task.isCancelled, generation == searchGeneration else { return }
            result = nextResult
            isSearching = false
            searchTask = nil
        }
    }
}

struct LocalDictionaryManagementView: View {
    @EnvironmentObject private var dictionaryStore: LocalDictionaryStore
    @State private var showsImporter = false
    @State private var importError: String?
    @State private var deleteTarget: LocalDictionaryPackage?

    var body: some View {
        List {
            Section {
                if let count = dictionaryStore.builtInIndexEntryCount {
                    Text("About \(count.formatted()) built-in entries. Lookup never uses the network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Dictionaries stay on this device. Lookup is offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Installed dictionaries") {
                if dictionaryStore.packs.isEmpty {
                    Text("No offline dictionaries")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dictionaryStore.packs) { pack in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pack.title).font(.headline)
                                Text("\(pack.totalEntryCount.formatted()) entries · \(pack.language)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let sourceSummary = pack.sourceSummary, !sourceSummary.isEmpty {
                                    Text(sourceSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if pack.id == "simple-study-official-dictionary" {
                                Text("Built-in")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if pack.id != "simple-study-official-dictionary" {
                                Button(role: .destructive) { deleteTarget = pack } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button { showsImporter = true } label: {
                    Label("Import JSON dictionary", systemImage: "square.and.arrow.down")
                }
                Text("Supports JSON dictionaries of words and phrases.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Add dictionary")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle("Offline dictionaries")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsImporter = true } label: {
                    Label("Import", systemImage: "plus")
                }
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json], onCompletion: importPackage)
        .confirmationDialog(
            "Delete this offline dictionary?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let deleteTarget else { return }
                do {
                    try dictionaryStore.removePack(id: deleteTarget.id)
                    self.deleteTarget = nil
                } catch {
                    importError = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Delete this device's dictionary index only. Word collections and review progress are kept.")
        }
        .alert("Dictionary action failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func importPackage(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            _ = try dictionaryStore.importPackage(data: Data(contentsOf: url))
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            content
        }
        .appCard(padding: 14)
    }
}

private struct VocabularyCoursewareView: View {
    @Query private var allUnits: [VocabularyUnitRecord]
    @Query private var allItems: [VocabularyItemRecord]

    let courseware: VocabularyCoursewareRecord

    private var units: [VocabularyUnitRecord] {
        allUnits
            .filter { $0.coursewareID == courseware.id && $0.isActive }
            .sorted { lhs, rhs in
                if lhs.sequence == rhs.sequence { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
                return lhs.sequence < rhs.sequence
            }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("First-pass progress")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(units.filter { $0.completedAt != nil }.count) / \(units.count) units")
                                .font(.title.bold())
                        }
                        Spacer()
                        if courseware.completedAt != nil {
                            Label("Completed", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    Text("Complete whole units. Difficult words return sooner for review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
            }

            Section("Study units") {
                ForEach(units) { unit in
                    NavigationLink(value: VocabularyRoute.review(coursewareID: courseware.id, unitID: unit.id)) {
                        VocabularyUnitRow(
                            unit: unit,
                            items: allItems.filter { $0.unitID == unit.id && $0.isActive }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(courseware.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: VocabularyRoute.review(coursewareID: courseware.id, unitID: nil)) {
                    Label("Review due words", systemImage: "play.fill")
                }
                .disabled(!allItems.contains { $0.coursewareID == courseware.id && $0.isActive && ($0.firstLearnedAt == nil || ($0.dueAt ?? .distantFuture) <= Date()) })
            }
        }
    }
}

private struct VocabularyUnitRow: View {
    let unit: VocabularyUnitRecord
    let items: [VocabularyItemRecord]

    private var learnedCount: Int { items.filter { $0.firstLearnedAt != nil }.count }
    private var dueCount: Int {
        items.filter { $0.firstLearnedAt == nil || ($0.dueAt ?? .distantFuture) <= Date() }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: unit.completedAt == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(unit.completedAt == nil ? AppTheme.accent : .green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(unit.sequence). \(unit.title)")
                    .font(.headline)
                HStack(spacing: 8) {
                    Text("\(learnedCount)/\(items.count) studied")
                    if dueCount > 0 { Text("· \(dueCount) due").foregroundStyle(.orange) }
                    if !unit.sourceLabel.isEmpty { Text("· \(unit.sourceLabel)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct VocabularyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var actionEngine: TodoActionEngine
    @Environment(\.dismiss) private var dismiss
    @Query private var allItems: [VocabularyItemRecord]

    let coursewareID: UUID?
    let unitID: UUID?
    var mode: VocabularySessionMode = .all

    @State private var queue: [UUID] = []
    @State private var currentIndex = 0
    @State private var isPrepared = false
    @State private var isAnswerShown = false
    @State private var weakCount = 0
    @State private var errorMessage: String?
    @State private var finishedAt: Date?

    private var currentItem: VocabularyItemRecord? {
        guard queue.indices.contains(currentIndex) else { return nil }
        let id = queue[currentIndex]
        return allItems.first(where: { $0.id == id })
    }

    private var title: String {
        if let currentItem, let unit = unit(for: currentItem) { return unit.title }
        return unitID == nil ? (mode == .newWords ? "Learn new words" : "Vocabulary review") : "Study units"
    }

    var body: some View {
        Group {
            if finishedAt != nil {
                VocabularyReviewSummary(
                    reviewedCount: queue.count,
                    weakCount: weakCount,
                    dismiss: dismiss.callAsFunction
                )
            } else if let currentItem {
                reviewCard(for: currentItem)
            } else if isPrepared {
                ContentUnavailableView {
                    Label(mode == .newWords ? "New words complete" : "Nothing due right now", systemImage: "checkmark.circle")
                } description: {
                    Text(mode == .newWords ? "Reviews will be scheduled based on your ratings." : "Come back when reviews are due. Your progress is saved.")
                }
            } else {
                ProgressView("Preparing your review…")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { prepareQueue() }
        .alert("Could not save progress", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func reviewCard(for item: VocabularyItemRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("\(min(currentIndex + 1, queue.count)) / \(queue.count)", systemImage: "rectangle.stack")
                    Spacer()
                    Text(item.learningState.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.learningState == .mastered ? .green : AppTheme.accent)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.term)
                            .font(.system(size: 39, weight: .bold, design: .rounded))
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        LocalDictionaryLookupButton(query: item.term)
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Look up this entry")
                    }

                    if !item.partOfSpeech.isEmpty { Text(item.partOfSpeech).font(.subheadline).foregroundStyle(.secondary) }
                    if !item.phoneticUK.isEmpty || !item.phoneticUS.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            if !item.phoneticUK.isEmpty { Text("UK \(item.phoneticUK)") }
                            if !item.phoneticUS.isEmpty { Text("US \(item.phoneticUS)") }
                        }
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                    }

                    if isAnswerShown {
                        Divider()
                        Text(item.meaning.isEmpty ? "No definition available" : item.meaning)
                            .font(.title3.weight(.semibold))
                        if !item.example.isEmpty {
                            Text(item.example)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if !item.note.isEmpty {
                            Label(item.note, systemImage: "note.text")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(padding: 22, radius: AppTheme.heroRadius)

                if !isAnswerShown {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { isAnswerShown = true }
                    } label: {
                        Label("Show meaning", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                        ForEach(VocabularyRating.allCases) { rating in
                            Button {
                                record(rating, item: item)
                            } label: {
                                Label(rating.title, systemImage: rating.systemImage)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(rating == .notKnown ? .red : rating == .fuzzy ? .orange : rating == .known ? .green : AppTheme.accent)
                        }
                    }
                }
            }
            .frame(maxWidth: 720)
            .padding(AppTheme.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
    }

    private func prepareQueue() {
        guard !isPrepared else { return }
        do {
            queue = try VocabularyReviewService
                .itemsDue(in: coursewareID, unitID: unitID, context: modelContext)
                .filter { mode == .all || (mode == .newWords ? $0.firstLearnedAt == nil : $0.firstLearnedAt != nil) }
                .map(\.id)
            isPrepared = true
        } catch {
            errorMessage = error.localizedDescription
            isPrepared = true
        }
    }

    private func unit(for item: VocabularyItemRecord) -> VocabularyUnitRecord? {
        (try? modelContext.fetch(FetchDescriptor<VocabularyUnitRecord>()))?.first(where: { $0.id == item.unitID })
    }

    private func record(_ rating: VocabularyRating, item: VocabularyItemRecord) {
        do {
            let outcome = try VocabularyReviewService.record(
                rating: rating,
                for: item,
                context: modelContext
            )
            if rating == .notKnown || rating == .fuzzy { weakCount += 1 }

            if outcome.unitDidComplete || outcome.coursewareDidComplete {
                Task {
                    if outcome.unitDidComplete {
                        await actionEngine.completeVocabularyTasks(
                            coursewareID: item.coursewareID,
                            unitID: item.unitID,
                            context: modelContext
                        )
                    }
                    if outcome.coursewareDidComplete {
                        await actionEngine.completeVocabularyTasks(
                            coursewareID: item.coursewareID,
                            unitID: nil,
                            context: modelContext
                        )
                    }
                }
            }

            currentIndex += 1
            isAnswerShown = false
            if currentIndex >= queue.count { finishedAt = Date() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct VocabularyReviewSummary: View {
    let reviewedCount: Int
    let weakCount: Int
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text("Review complete")
                .font(.title.bold())
            Text("Reviewed \(reviewedCount) entries" + (weakCount == 0 ? "." : " · \(weakCount) will return sooner."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Back to Words") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .background(AppTheme.pageBackground)
    }
}

private struct VocabularyImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let package: VocabularyCoursewarePackage
    let sourceFileName: String

    @State private var importError: String?
    @State private var groupingMode: VocabularyGroupingMode = .singleUnit
    @State private var chunkSize = 20

    private var itemCount: Int { package.units.reduce(0) { $0 + $1.items.count } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Collection", value: package.title)
                    LabeledContent("Source", value: sourceFileName)
                    LabeledContent("Study units", value: "\(package.units.count)")
                    LabeledContent("Entry", value: "\(itemCount)")
                }

                Section("Units to import") {
                    ForEach(Array(package.units.enumerated()), id: \.offset) { index, unit in
                        HStack {
                            Text("\(unit.sequence). \(unit.title)")
                            Spacer()
                            Text("\(unit.items.count) words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Unit \(index + 1), \(unit.title), \(unit.items.count) entries")
                    }
                }

                Section {
                    Text("Matching IDs update the collection while keeping review progress. Imported data is saved locally first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !package.sourceHasExplicitUnits {
                    Section {
                        Picker("Grouping", selection: $groupingMode) {
                            ForEach(VocabularyGroupingMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.inline)

                        if groupingMode == .fixedSize {
                            Stepper("\(chunkSize) words per group", value: $chunkSize, in: 5...200, step: 5)
                        }

                        Text("Keep an ungrouped list together or split it by word count.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Ungrouped list")
                    }
                }
            }
            .navigationTitle("Review import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importPackage() }
                }
            }
            .alert("Import failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func importPackage() {
        do {
            let packageToImport = package.regrouped(for: groupingMode, chunkSize: chunkSize)
            _ = try VocabularyCoursewareService.importPackage(
                packageToImport,
                sourceFileName: sourceFileName,
                context: modelContext
            )
            dismiss()
        } catch {
            importError = error.localizedDescription
        }
    }
}

struct VocabularyFormatView: View {
    @State private var exportURL: URL?

    private var text: String {
        guard let data = try? VocabularyCoursewareService.exampleData() else { return "Could not generate the example." }
        return String(data: data, encoding: .utf8) ?? "The example is not valid UTF-8."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Word collection JSON · schemaVersion 1")
                    .font(.headline)
                Text("Each item in units is a study unit with its own name and key. Ungrouped lists can be split on import.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(padding: 14, radius: AppTheme.cardRadius)
            }
            .padding(AppTheme.pagePadding)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("Format example")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task {
            guard exportURL == nil, let data = try? VocabularyCoursewareService.exampleData() else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("vocabulary-courseware-example.json")
            try? data.write(to: url, options: .atomic)
            exportURL = url
        }
    }
}

struct LocalDictionaryFormatView: View {
    @State private var exportURL: URL?

    private var text: String {
        guard let data = try? LocalDictionaryPackageService.exampleData() else { return "Could not generate the example." }
        return String(data: data, encoding: .utf8) ?? "The example is not valid UTF-8."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Offline dictionary JSON · schemaVersion 1")
                    .font(.headline)
                Text("Supports words, phrases, parts of speech, pronunciation, and definitions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(padding: 14, radius: AppTheme.cardRadius)
            }
            .padding(AppTheme.pagePadding)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("Dictionary format example")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task {
            guard exportURL == nil, let data = try? LocalDictionaryPackageService.exampleData() else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictionary-example.json")
            try? data.write(to: url, options: .atomic)
            exportURL = url
        }
    }
}
