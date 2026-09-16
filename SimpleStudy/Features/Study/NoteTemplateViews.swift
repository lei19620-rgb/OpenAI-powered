import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct NoteTemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NoteTemplateRecord.name) private var templates: [NoteTemplateRecord]
    @State private var editingTemplate: NoteTemplateRecord?
    @State private var createsTemplate = false
    @State private var showsImporter = false
    @State private var importError: String?
    @State private var exportURLs: [UUID: URL] = [:]

    var body: some View {
        List {
            Section {
                ForEach(templates) { template in
                    HStack {
                        Button { editingTemplate = template } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(template.name).font(.headline).foregroundStyle(.primary)
                                    Text("v\(template.version)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                                Text(template.details.isEmpty ? "\(template.blocks.count) blocks" : template.details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                            Spacer()
                            if let url = exportURLs[template.id] {
                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Export \(template.name)")
                            }
                    }
                    .swipeActions {
                        Button("Copy") { duplicate(template) }
                            .tint(AppTheme.accent)
                    }
                }
            } footer: {
                Text("Changes affect new notes only. Existing notes stay unchanged.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle("Note templates")
        .task(id: templates.map { "\($0.id)-\($0.version)-\($0.updatedAt)" }) {
            for template in templates { exportURLs[template.id] = exportURL(for: template) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showsImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                Button { createsTemplate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $createsTemplate) {
            NoteTemplateEditorView(template: nil)
        }
        .sheet(item: $editingTemplate) { template in
            NoteTemplateEditorView(template: template)
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
            importTemplate(result)
        }
        .alert("Template action failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func duplicate(_ template: NoteTemplateRecord) {
        let copy = NoteTemplateRecord(
            name: "\(template.name) copy",
            details: template.details,
            blocks: template.blocks
        )
        modelContext.insert(copy)
        do { try modelContext.save() } catch { modelContext.rollback(); importError = error.localizedDescription }
    }

    private func exportURL(for template: NoteTemplateRecord) -> URL? {
        guard let data = try? NoteTemplatePackageService.exportData(for: template) else { return nil }
        let safeName = template.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).sstemplate.json")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    private func importTemplate(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > NoteTemplatePackageService.maximumFileSize {
                throw NoteTemplateImportError.fileTooLarge
            }
            let package = try NoteTemplatePackageService.decodeAndValidate(Data(contentsOf: url))
            modelContext.insert(NoteTemplateRecord(
                name: package.name,
                details: package.details,
                blocks: package.blocks
            ))
            try modelContext.save()
        } catch {
            modelContext.rollback()
            importError = error.localizedDescription
        }
    }
}

private struct NoteTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let template: NoteTemplateRecord?

    @State private var name: String
    @State private var details: String
    @State private var blocks: [NoteBlock]
    @State private var saveError: String?

    init(template: NoteTemplateRecord?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "New note template")
        _details = State(initialValue: template?.details ?? "")
        _blocks = State(initialValue: template?.blocks ?? [
            NoteBlock(kind: .heading, title: "📝 {{course}} · Day {{day}}"),
            NoteBlock(kind: .richText, title: "✍️ Notes")
        ])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $details, axis: .vertical)
                }

                Section {
                    ForEach(blocks.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Type", selection: $blocks[index].kind) {
                                ForEach(NoteBlockKind.allCases) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }
                            TextField("Block title; supports {{course}}, {{day}}, {{date}}", text: $blocks[index].title)
                            TextField("Placeholder", text: $blocks[index].placeholder, axis: .vertical)
                            HStack {
                                Button { if index > 0 { blocks.swapAt(index, index - 1) } } label: { Image(systemName: "arrow.up") }
                                    .disabled(index == 0)
                                Button { if index < blocks.count - 1 { blocks.swapAt(index, index + 1) } } label: { Image(systemName: "arrow.down") }
                                    .disabled(index == blocks.count - 1)
                                Spacer()
                                Button(role: .destructive) { blocks.remove(at: index) } label: { Image(systemName: "trash") }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Menu {
                        ForEach(NoteBlockKind.allCases) { kind in
                            Button(kind.title) { blocks.append(NoteBlock(kind: kind, title: kind.suggestedTitle)) }
                        }
                    } label: {
                        Label("Add block", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Blocks")
                } footer: {
                    Text("Template variables are resolved only when creating a note.")
                }
            }
            .navigationTitle(template == nil ? "New template" : "Edit template")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Template not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || blocks.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let template {
            template.name = name
            template.details = details
            template.blocks = blocks
            template.version += 1
            template.updatedAt = Date()
        } else {
            modelContext.insert(NoteTemplateRecord(name: name, details: details, blocks: blocks))
        }
        do { try modelContext.save(); dismiss() } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}
