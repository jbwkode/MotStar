import SwiftUI
import AppKit

/// Right pane: toolbar (Share / Email / Print / Export / mode) above the
/// preview or source editor. Markdown and text files get an Edit/Preview
/// toggle plus a Save button while editing; leaving the editor with unsaved
/// changes prompts Save / Discard / Cancel. `.md` previews can be formatted
/// or raw (⇧⌘R). Everything routes through the shared `AppState`.
struct PreviewPane: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if app.paneMode == .editor && app.selectedKind == .markdown {
                markdownFormatBar
            }
            if showsDraftBanner {
                unsavedDraftBanner
            }
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert(item: $app.activeAlert) { item in
            Alert(title: Text(item.title),
                  message: Text(item.message),
                  dismissButton: .default(Text("OK")))
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            if let url = app.selectedURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share the selected file")

                Button {
                    app.emailSelectedFile()
                } label: {
                    Label("Email", systemImage: "envelope")
                }
                .help("Email the selected file via Outlook (⇧⌘M)")

                Button {
                    app.printSelectedFile()
                } label: {
                    Label("Print", systemImage: "printer")
                }
                .help("Print the selected file (⌘P)")
                .disabled(app.isWorking)

                Button {
                    app.exportSelectedFileAsPDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.down")
                }
                .help("Export the selected file as a PDF (⇧⌘E)")
                .disabled(app.isWorking)

                if AppState.isEditable(FileTypeRegistry.kind(for: url)) {
                    Divider().frame(height: 16)

                    Picker("Mode", selection: modeBinding) {
                        Text("Preview").tag(FilePaneMode.preview)
                        Text("Edit").tag(FilePaneMode.editor)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 180)
                    .help("Toggle between preview and editing (⌘E)")

                    if app.paneMode == .editor {
                        Button {
                            app.saveActiveDocument()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                        .help("Save the document (⌘S)")
                        .disabled(!(app.activeDocument?.isDirty ?? false))

                        Button {
                            app.revertActiveDocument()
                        } label: {
                            Label("Revert", systemImage: "arrow.uturn.backward")
                                .labelStyle(.iconOnly)
                        }
                        .help("Discard changes and reload from disk (⌥⌘R)")
                        .disabled(!(app.activeDocument?.isDirty ?? false))
                    }
                }

                if app.selectedKind == .markdown && app.paneMode == .preview {
                    Picker("Markdown display", selection: $app.markdownDisplayMode) {
                        ForEach(MarkdownDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 170)
                    .help("Show formatted Markdown or the raw source (⇧⌘R)")
                }

                if app.selectedKind == .markdown {
                    Button {
                        app.toggleOutline()
                    } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    .help("Show Document Outline (⌥⌘O)")
                    .disabled(app.paneMode == .preview && app.markdownDisplayMode == .raw)
                }

                Button {
                    app.zoomFont(by: -1)
                } label: {
                    Text("A−")
                        .font(.system(size: 11, weight: .semibold))
                }
                .help("Zoom Out (⌘−)")

                Button {
                    app.zoomFont(by: 1)
                } label: {
                    Text("A+")
                        .font(.system(size: 13, weight: .semibold))
                }
                .help("Zoom In (⌘+)")
            } else {
                Button { } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    .disabled(true)
                Button { } label: { Label("Email", systemImage: "envelope") }
                    .disabled(true)
                Button { } label: { Label("Print", systemImage: "printer") }
                    .disabled(true)
                Button { } label: { Label("Export PDF", systemImage: "square.and.arrow.down") }
                    .disabled(true)
            }

            Spacer()

            if let url = app.selectedURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var modeBinding: Binding<FilePaneMode> {
        Binding(
            get: { app.paneMode },
            set: { newValue in
                if newValue == .editor {
                    app.editSelectedFile()
                } else {
                    app.showPreview()
                }
            }
        )
    }

    // MARK: Preview content

    /// True while the preview is showing an unsaved editor draft, so the
    /// banner offering Save / Discard is visible.
    private var showsDraftBanner: Bool {
        app.paneMode == .preview
            && (app.activeDocument?.isDirty ?? false)
            && app.activeDocument?.url == app.selectedURL
    }

    /// Shown above the preview when the pane is displaying unsaved edits, so
    /// the user can keep or abandon them without hunting through the menus.
    private var unsavedDraftBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.orange)
            Text("Showing unsaved edits")
                .font(.callout)
            Spacer()
            Button("Save") {
                app.saveActiveDocument()
            }
            Button("Discard…") {
                app.revertActiveDocument()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    @ViewBuilder private var content: some View {
        if let url = app.selectedURL {
            switch FileTypeRegistry.kind(for: url) {
            case .markdown:
                if app.paneMode == .editor {
                    editorView(for: url)
                } else if app.markdownDisplayMode == .formatted {
                    FormattedMarkdownView(url: url,
                                          textOverride: app.draftTextForSelection,
                                          wikilinkRoots: app.roots.map(\.url),
                                          textSize: app.readingFontSize)
                } else {
                    TextPreviewView(url: url,
                                    textOverride: app.draftTextForSelection,
                                    fontSize: app.readingFontSize)
                }
            case .text:
                if app.paneMode == .editor {
                    editorView(for: url)
                } else {
                    TextPreviewView(url: url,
                                    textOverride: app.draftTextForSelection,
                                    fontSize: app.readingFontSize)
                }
            case .code:
                if app.paneMode == .editor {
                    editorView(for: url)
                } else {
                    CodePreviewView(url: url, textSize: app.readingFontSize)
                }
            case .image:
                ImagePreviewView(url: url)
            default:
                QuickLookView(url: url)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        } else {
            emptyState
        }
    }

    @ViewBuilder private func editorView(for url: URL) -> some View {
        if let document = app.activeDocument, document.url == url {
            SourceEditorView(document: document, wrap: app.wordWrapEnabled, fontSize: app.editorFontSize)
        } else {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading editor…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                app.editSelectedFile()
            }
        }
    }

    // MARK: Markdown format bar (visible while editing a .md file)

    private struct FormatButtonSpec: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let format: AppState.MarkdownFormat
    }

    private var markdownFormatBar: some View {
        let specs: [FormatButtonSpec] = [
            FormatButtonSpec(title: "H1", systemImage: "textformat.size", format: .heading(level: 1)),
            FormatButtonSpec(title: "H2", systemImage: "textformat.size", format: .heading(level: 2)),
            FormatButtonSpec(title: "H3", systemImage: "textformat.size", format: .heading(level: 3)),
            FormatButtonSpec(title: "Bold", systemImage: "bold", format: .bold),
            FormatButtonSpec(title: "Italic", systemImage: "italic", format: .italic),
            FormatButtonSpec(title: "Code", systemImage: "chevron.left.forwardslash.chevron.right", format: .inlineCode),
            FormatButtonSpec(title: "Quote", systemImage: "text.quote", format: .blockquote),
            FormatButtonSpec(title: "List", systemImage: "list.bullet", format: .bulletList),
            FormatButtonSpec(title: "Numbered", systemImage: "list.number", format: .numberedList),
            FormatButtonSpec(title: "Link", systemImage: "link", format: .link),
            FormatButtonSpec(title: "Image", systemImage: "photo", format: .image)
        ]
        return HStack(spacing: 6) {
            ForEach(specs) { spec in
                Button {
                    app.applyMarkdownFormat(spec.format)
                } label: {
                    Label(spec.title, systemImage: spec.systemImage)
                        .labelStyle(.iconOnly)
                }
                .help(spec.title)
            }
            Spacer()
            Text("Markdown tools")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar.opacity(0.6))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Select a file to preview it")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    app.createNewMarkdownFile()
                } label: {
                    Label("New Markdown File", systemImage: "doc.badge.plus")
                }
                Button {
                    app.showAddFolder = true
                } label: {
                    Label("Add Folder…", systemImage: "folder.badge.plus")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Plain text preview (monospaced, selectable). Pass `textOverride` to show
/// an unsaved editor draft.
struct TextPreviewView: View {
    let url: URL
    var textOverride: String?
    var fontSize: Double = 15

    var body: some View {
        ScrollView {
            if let text = textOverride ?? Self.loadText(url) {
                Text(text)
                    .font(.system(size: fontSize).monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            } else {
                Text("Cannot read this text file.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private static func loadText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
    }
}
