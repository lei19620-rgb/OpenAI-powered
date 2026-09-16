import PDFKit
import CryptoKit
import PencilKit
import SwiftData
import SwiftUI

private enum PDFDrawingToolMode {
    case pen
    case eraser
}

private enum PDFCanvasCommandKind {
    case undo
    case redo
}

private struct PDFCanvasCommand: Equatable {
    let id = UUID()
    let kind: PDFCanvasCommandKind
}

struct PDFStudyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allAnnotations: [PDFAnnotationRecord]

    let asset: StudyAssetRecord
    let onOCR: () -> Void
    let onCancelOCR: () -> Void
    let isOCRRunning: Bool
    let ocrProgress: Double
    var onExplain: ((AIStudySource) -> Void)? = nil

    @State private var searchTerm = ""
    @State private var drawingEnabled = false
    @State private var drawingTool: PDFDrawingToolMode = .pen
    @State private var canvasCommand: PDFCanvasCommand?
    @State private var showsThumbnails = UIDevice.current.userInterfaceIdiom == .pad
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var selectedText = ""
    @State private var selectedPage: Int?
    @State private var dictionaryQuery = ""
    @State private var showsDictionary = false
    @State private var dictionarySelectionTask: Task<Void, Never>?
    @State private var unsavedDrawings: [Int: Data] = [:]

    private var annotations: [PDFAnnotationRecord] {
        allAnnotations.filter { $0.assetID == asset.id }
    }

    private var drawings: [Int: Data] {
        Dictionary(annotations.sorted { $0.updatedAt < $1.updatedAt }.map { ($0.pageIndex, $0.drawingData) },
                   uniquingKeysWith: { _, newest in newest })
            .merging(unsavedDrawings, uniquingKeysWith: { _, current in current })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search PDF", text: $searchTerm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))

                if let selectedDictionaryQuery {
                    Button {
                        presentDictionary(for: selectedDictionaryQuery)
                    } label: {
                        Label("Look up", systemImage: "character.book.closed")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Look up the selected word or phrase in this PDF")
                    .accessibilityHint("Uses only offline dictionaries")
                }

                Button {
                    drawingEnabled.toggle()
                } label: {
                    Label(drawingEnabled ? "Stop drawing" : "Pencil", systemImage: drawingEnabled ? "pencil.slash" : "applepencil")
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .tint(drawingEnabled ? .orange : AppTheme.accent)

                Button {
                    showsThumbnails.toggle()
                } label: {
                    Image(systemName: showsThumbnails ? "rectangle.grid.1x2.fill" : "rectangle.grid.1x2")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(showsThumbnails ? "Hide thumbnails" : "Show thumbnails")

                Menu {
                    if let onExplain {
                        Button {
                            dictionarySelectionTask?.cancel()
                            showsDictionary = false
                            onExplain(AIStudySource(text: selectedText, title: asset.displayName,
                                workspaceID: asset.workspaceID, assetID: asset.id, page: selectedPage))
                        } label: { Label("Explain selected text", systemImage: "sparkles") }
                            .disabled(selectedText.isEmpty)
                    }
                    Button(action: onOCR) {
                        Label(isOCRRunning ? "Recognizing text" : "Recognize all text", systemImage: "text.viewfinder")
                    }
                    .disabled(isOCRRunning)

                    if isOCRRunning {
                        Button(role: .destructive, action: onCancelOCR) {
                            Label("Cancel OCR (\(ocrProgress.formatted(.percent.precision(.fractionLength(0)))))", systemImage: "xmark.circle")
                        }
                    }

                    Button(action: exportAnnotatedPDF) {
                        Label("Export annotated PDF", systemImage: "square.and.arrow.up")
                    }

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share exported file", systemImage: "paperplane")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("PDF tools")
            }
            .padding(10)
            .background(.bar)

            if !selectedText.isEmpty, let onExplain {
                HStack(spacing: 12) {
                    Text(selectedText).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        dictionarySelectionTask?.cancel(); showsDictionary = false
                        onExplain(AIStudySource(text: selectedText, title: asset.displayName,
                            workspaceID: asset.workspaceID, assetID: asset.id, page: selectedPage,
                            contentHash: SHA256.hash(data: Data(selectedText.utf8)).map { String(format: "%02x", $0) }.joined()))
                    } label: { Label("Explain", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).controlSize(.regular)
                }.padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
            }

            if !unsavedDrawings.isEmpty {
                HStack {
                    Label("Annotations not saved", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Spacer()
                    Button("Try again") {
                        for (page, data) in unsavedDrawings { saveDrawing(pageIndex: page, data: data) }
                    }
                }
                .font(.subheadline)
                .padding(.horizontal)
            }

            if drawingEnabled {
                HStack(spacing: 12) {
                    Picker("Drawing tool", selection: $drawingTool) {
                        Label("Pen", systemImage: "pencil.tip").tag(PDFDrawingToolMode.pen)
                        Label("Eraser", systemImage: "eraser").tag(PDFDrawingToolMode.eraser)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)

                    Button {
                        canvasCommand = PDFCanvasCommand(kind: .undo)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .accessibilityLabel("Undo")

                    Button {
                        canvasCommand = PDFCanvasCommand(kind: .redo)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .accessibilityLabel("Redo")

                    Spacer()
                    Text(UIDevice.current.userInterfaceIdiom == .pad ? "Draw with Apple Pencil" : "Draw with your finger")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }

            PDFKitView(
                data: asset.fileData,
                searchTerm: searchTerm,
                drawingEnabled: drawingEnabled,
                drawingTool: drawingTool,
                command: canvasCommand,
                showsThumbnails: showsThumbnails,
                initialDrawings: drawings,
                onDrawingChanged: saveDrawing,
                onSelectionChanged: { value, page in
                    selectedPage = page
                    handleSelectionChange(value)
                }
            )
        }
        .popover(isPresented: $showsDictionary, arrowEdge: .top) {
            LocalDictionaryLookupView(query: dictionaryQuery)
        }
        .alert("PDF action failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .onDisappear {
            dictionarySelectionTask?.cancel()
            dictionarySelectionTask = nil
        }
    }

    private var selectedDictionaryQuery: String? {
        DictionarySelectionQuery.normalized(from: selectedText)
    }

    private func handleSelectionChange(_ value: String?) {
        selectedText = value ?? ""
        dictionarySelectionTask?.cancel()
        dictionarySelectionTask = nil

        guard let query = DictionarySelectionQuery.normalized(from: value) else {
            dictionaryQuery = ""
            showsDictionary = false
            return
        }

        dictionaryQuery = query
        dictionarySelectionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            showsDictionary = true
            dictionarySelectionTask = nil
        }
    }

    private func presentDictionary(for query: String) {
        dictionarySelectionTask?.cancel()
        dictionarySelectionTask = nil
        dictionaryQuery = query
        showsDictionary = true
    }

    private func saveDrawing(pageIndex: Int, data: Data) {
        unsavedDrawings[pageIndex] = data
        exportURL = nil
        let current = ((try? modelContext.fetch(FetchDescriptor<PDFAnnotationRecord>())) ?? [])
            .filter { $0.assetID == asset.id && $0.pageIndex == pageIndex }
            .max { $0.updatedAt < $1.updatedAt }
        if let existing = current {
            existing.drawingData = data
            existing.updatedAt = Date()
        } else {
            modelContext.insert(PDFAnnotationRecord(assetID: asset.id, pageIndex: pageIndex, drawingData: data))
        }
        do {
            try modelContext.save()
            unsavedDrawings.removeValue(forKey: pageIndex)
        } catch {
            modelContext.rollback()
            exportError = "Annotations were not saved. Try again or export an annotated PDF. \(error.localizedDescription)"
        }
    }

    private func exportAnnotatedPDF() {
        do {
            let data = try PDFExportService.annotatedPDF(source: asset.fileData, drawings: drawings)
            let name = asset.displayName.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-annotated.pdf")
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let data: Data
    let searchTerm: String
    let drawingEnabled: Bool
    let drawingTool: PDFDrawingToolMode
    let command: PDFCanvasCommand?
    let showsThumbnails: Bool
    let initialDrawings: [Int: Data]
    let onDrawingChanged: (Int, Data) -> Void
    let onSelectionChanged: (String?, Int?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialDrawings: initialDrawings,
            onDrawingChanged: onDrawingChanged,
            onSelectionChanged: onSelectionChanged
        )
    }

    func makeUIView(context: Context) -> PDFReaderContainerView {
        let container = PDFReaderContainerView()
        let view = container.pdfView
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageOverlayViewProvider = context.coordinator
        context.coordinator.observeSelection(of: view)
        context.coordinator.install(data: data, in: view)
        container.setShowsThumbnails(showsThumbnails)
        return container
    }

    func updateUIView(_ container: PDFReaderContainerView, context: Context) {
        let view = container.pdfView
        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onSelectionChanged = onSelectionChanged
        context.coordinator.updateDrawings(initialDrawings)
        context.coordinator.setDrawingEnabled(drawingEnabled)
        context.coordinator.setDrawingTool(drawingTool)
        context.coordinator.install(data: data, in: view)
        context.coordinator.search(searchTerm, in: view)
        context.coordinator.apply(command: command, in: view)
        container.setShowsThumbnails(showsThumbnails)
    }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider, PKCanvasViewDelegate {
        var onDrawingChanged: (Int, Data) -> Void
        var onSelectionChanged: (String?, Int?) -> Void
        private var drawingData: [Int: Data]
        private var canvases: [Int: PKCanvasView] = [:]
        private var dataSignature: Int?
        private var lastSearch = ""
        private var drawingEnabled = false
        private var drawingTool: PDFDrawingToolMode = .pen
        private var lastCommandID: UUID?
        private var selectionObserver: NSObjectProtocol?

        init(
            initialDrawings: [Int: Data],
            onDrawingChanged: @escaping (Int, Data) -> Void,
            onSelectionChanged: @escaping (String?, Int?) -> Void
        ) {
            self.drawingData = initialDrawings
            self.onDrawingChanged = onDrawingChanged
            self.onSelectionChanged = onSelectionChanged
        }

        deinit {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
        }

        func observeSelection(of view: PDFView) {
            selectionObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewSelectionChanged,
                object: view,
                queue: .main
            ) { [weak self] notification in
                let pdfView = notification.object as? PDFView
                let selection = pdfView?.currentSelection
                let page = selection?.pages.first.flatMap { pdfView?.document?.index(for: $0) }.map { $0 + 1 }
                self?.onSelectionChanged(selection?.string, page)
            }
        }

        func install(data: Data, in view: PDFView) {
            let signature = data.hashValue
            guard dataSignature != signature else { return }
            dataSignature = signature
            view.document = PDFDocument(data: data)
            view.autoScales = true
        }

        func updateDrawings(_ updated: [Int: Data]) {
            drawingData = updated
        }

        func setDrawingEnabled(_ enabled: Bool) {
            drawingEnabled = enabled
            for canvas in canvases.values {
                canvas.isUserInteractionEnabled = enabled
            }
        }

        func setDrawingTool(_ tool: PDFDrawingToolMode) {
            drawingTool = tool
            for canvas in canvases.values { applyTool(to: canvas) }
        }

        func apply(command: PDFCanvasCommand?, in view: PDFView) {
            guard let command, command.id != lastCommandID else { return }
            lastCommandID = command.id
            guard let document = view.document,
                  let page = view.currentPage else { return }
            let index = document.index(for: page)
            guard let canvas = canvases[index] else { return }
            switch command.kind {
            case .undo: canvas.undoManager?.undo()
            case .redo: canvas.undoManager?.redo()
            }
            onDrawingChanged(index, canvas.drawing.dataRepresentation())
        }

        func search(_ text: String, in view: PDFView) {
            guard text != lastSearch else { return }
            lastSearch = text
            guard !text.isEmpty, let document = view.document else {
                view.clearSelection()
                return
            }
            guard let first = document.findString(text, withOptions: .caseInsensitive).first else { return }
            view.setCurrentSelection(first, animate: true)
            view.go(to: first)
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            guard let document = view.document else { return nil }
            let index = document.index(for: page)
            if let existing = canvases[index] { return existing }

            let canvas = PKCanvasView()
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.drawingPolicy = UIDevice.current.userInterfaceIdiom == .pad ? .pencilOnly : .anyInput
            applyTool(to: canvas)
            canvas.isUserInteractionEnabled = drawingEnabled
            canvas.delegate = self
            canvas.accessibilityIdentifier = String(index)
            if let data = drawingData[index], let drawing = try? PKDrawing(data: data) {
                canvas.drawing = drawing
            }
            canvases[index] = canvas
            return canvas
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let canvas = overlayView as? PKCanvasView,
                  let document = pdfView.document else { return }
            let index = document.index(for: page)
            onDrawingChanged(index, canvas.drawing.dataRepresentation())
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let index = Int(canvasView.accessibilityIdentifier ?? "") else { return }
            onDrawingChanged(index, canvasView.drawing.dataRepresentation())
        }

        private func applyTool(to canvas: PKCanvasView) {
            switch drawingTool {
            case .pen:
                canvas.tool = PKInkingTool(.pen, color: .systemBlue, width: 3)
            case .eraser:
                canvas.tool = PKEraserTool(.bitmap)
            }
        }
    }
}

private final class PDFReaderContainerView: UIView {
    let pdfView = PDFView()
    private let thumbnailView = PDFThumbnailView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [pdfView, thumbnailView])
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: 88)
        ])
        thumbnailView.pdfView = pdfView
        thumbnailView.layoutMode = .horizontal
        thumbnailView.thumbnailSize = CGSize(width: 58, height: 76)
        thumbnailView.backgroundColor = .secondarySystemBackground
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setShowsThumbnails(_ shows: Bool) {
        thumbnailView.isHidden = !shows
    }
}

enum PDFExportService {
    static func annotatedPDF(source: Data, drawings: [Int: Data]) throws -> Data {
        guard let document = PDFDocument(data: source) else { throw PDFProcessingError.invalidPDF }
        let output = NSMutableData()
        UIGraphicsBeginPDFContextToData(output, .zero, nil)
        defer { UIGraphicsEndPDFContext() }

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            UIGraphicsBeginPDFPageWithInfo(bounds, nil)
            guard let context = UIGraphicsGetCurrentContext() else { continue }
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()

            if let data = drawings[index], let drawing = try? PKDrawing(data: data) {
                drawing.image(from: bounds, scale: 1).draw(in: bounds)
            }
        }
        return output as Data
    }
}
