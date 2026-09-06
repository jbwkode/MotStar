import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

// MARK: - Supporting types

/// A user-chosen root folder, persisted across launches (ADR-002).
struct RootFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var path: String
    var addedAt: Date

    init(path: String, addedAt: Date = Date()) {
        self.id = UUID()
        self.path = path
        self.addedAt = addedAt
    }

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var isReachable: Bool { FileManager.default.fileExists(atPath: path) }
}

/// Loads/saves the root folder list (JSON in UserDefaults).
final class PersistenceService {
    private let key = "navstar.rootFolders.v1"

    func load() -> [RootFolder] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RootFolder].self, from: data)) ?? []
    }

    func save(_ roots: [RootFolder]) {
        if let data = try? JSONEncoder().encode(roots) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Alert payload surfaced by shared actions (toolbar and menu).
struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Right-pane mode for editable files: read/preview or source editing.
enum FilePaneMode {
    case preview
    case editor
}

// MARK: - App state

/// Application-wide state: root folders, the lazy tree, selection, editor
/// documents, expansions and the shared preview actions (toolbar buttons and
/// menu commands all call the same code paths here).
@MainActor
final class AppState: ObservableObject {
    /// Single shared instance so menu commands and views stay in sync.
    static let shared = AppState()

    @Published var roots: [RootFolder] = []
    @Published var rootNodes: [TreeNode] = []
    @Published var selectedURL: URL?
    @Published var showAddFolder = false
    @Published var markdownDisplayMode: MarkdownDisplayMode = .formatted
    @Published var paneMode: FilePaneMode = .preview
    @Published var expandedPaths: Set<String> = []
    @Published var activeDocument: TextDocument?
    @Published var activeAlert: AlertItem?
    @Published var isWorking = false
    @Published var isFocusMode = false
    @Published var wordWrapEnabled = true

    /// Weak reference to the live source editor text view (set by
    /// `SourceEditorView`) so markdown-format commands can act on the
    /// current selection.
    weak var activeEditorTextView: NSTextView?

    private let persistence = PersistenceService()
    /// Keeps TreeNode instances stable per path so expansion state survives
    /// list rebuilds and folder removals.
    private var nodeCache: [String: TreeNode] = [:]
    /// Live folder watching (FSEvents) keeps the tree fresh on external edits.
    private var watcher: FolderWatcher?
    private var pendingExternalReload: DispatchWorkItem?

    init() {
        roots = persistence.load().sorted { $0.addedAt < $1.addedAt }
        rebuildRootNodes()
        let initialPaths = roots.map(\.path)
        watcher = FolderWatcher(paths: initialPaths) { [weak self] changedPaths in
            DispatchQueue.main.async {
                self?.handleFolderEvents(changedPaths)
            }
        }
        watcher?.start()
    }

    // MARK: Live external changes (FSEvents)

    private func handleFolderEvents(_ changedPaths: [String]) {
        guard !changedPaths.isEmpty else { return }
        let affected = Set(roots.filter { root in
            changedPaths.contains { changed in
                changed == root.path || changed.hasPrefix(root.path + "/")
            }
        }.map(\.path))
        guard !affected.isEmpty else { return }

        pendingExternalReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyExternalReload(rootPaths: affected)
        }
        pendingExternalReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func applyExternalReload(rootPaths: Set<String>) {
        for path in rootPaths {
            guard let node = nodeCache[path] else { continue }
            node.reload()
            if expandedPaths.contains(path) {
                node.loadChildrenIfNeeded()
            }
        }
        NSLog("MotStar: FSEvents — reloaded roots %@", rootPaths.sorted().joined(separator: ", "))
    }

    // MARK: Kind helpers

    static func isEditable(_ kind: FileKind) -> Bool {
        kind == .markdown || kind == .text
    }

    var selectedKind: FileKind? {
        guard let url = selectedURL else { return nil }
        return FileTypeRegistry.kind(for: url)
    }

    var isSelectionEditable: Bool {
        guard let kind = selectedKind else { return false }
        return Self.isEditable(kind)
    }

    /// Draft text of the selected file when an unsaved editor document exists.
    var draftTextForSelection: String? {
        guard let doc = activeDocument, doc.url == selectedURL else { return nil }
        return doc.text
    }

    // MARK: Folder mutations

    func addFolders(urls: [URL]) {
        var changed = false
        for url in urls {
            let path = url.path
            guard !roots.contains(where: { $0.path == path }) else { continue }
            roots.append(RootFolder(path: path))
            changed = true
        }
        guard changed else { return }
        persistAndRebuild()
    }

    func remove(_ root: RootFolder) {
        roots.removeAll { $0.id == root.id }
        if let selected = selectedURL, selected.path.hasPrefix(root.path + "/") {
            selectedURL = nil
        }
        persistAndRebuild()
    }

    /// TreeNode identity for a root folder (stable across renders).
    func treeNode(for root: RootFolder) -> TreeNode {
        if let node = nodeCache[root.path] { return node }
        let node = TreeNode(url: root.url)
        nodeCache[root.path] = node
        return node
    }

    private func rootFolder(containing url: URL) -> RootFolder? {
        roots.first { url.path == $0.path || url.path.hasPrefix($0.path + "/") }
    }

    // MARK: Selection & tree expansion

    func isExpanded(_ path: String) -> Bool { expandedPaths.contains(path) }

    func setExpanded(_ path: String, _ expanded: Bool) {
        if expanded {
            expandedPaths.insert(path)
        } else {
            expandedPaths.remove(path)
        }
    }

    /// Selects a file, prompting about unsaved changes in the editor first.
    func selectFile(_ url: URL) {
        guard url != selectedURL || activeDocument != nil else { return }
        if let doc = activeDocument, doc.isDirty, doc.url != url {
            let response = confirmUnsavedChanges()
            switch response {
            case .alertFirstButtonReturn: // Save
                do { try doc.save() } catch {
                    activeAlert = AlertItem(title: "Save", message: error.localizedDescription)
                    return
                }
            case .alertSecondButtonReturn: // Discard
                break
            default: // Cancel
                return
            }
        }
        activeDocument = nil
        selectedURL = url
        paneMode = .preview
    }

    /// Expands the tree along the folder path to a file and selects it.
    func revealAndSelect(_ url: URL) {
        guard let root = rootFolder(containing: url) else {
            selectedURL = url
            return
        }
        let rootNode = treeNode(for: root)
        expandedPaths.insert(root.url.path)

        let parent = url.deletingLastPathComponent()
        let segments = folderSegments(from: root.url, to: parent)

        Task { @MainActor in
            var node = rootNode
            var currentDir = root.url
            for segment in segments {
                await ensureLoaded(node)
                guard let child = node.children?.first(where: { $0.isFolder && $0.name == segment }) else {
                    break
                }
                currentDir.appendPathComponent(segment)
                expandedPaths.insert(currentDir.path)
                node = child
            }
            await ensureLoaded(node) // make sure the file row exists
            selectFile(url)
        }
    }

    private func folderSegments(from root: URL, to parent: URL) -> [String] {
        let rootCount = root.pathComponents.count
        guard parent.pathComponents.count > rootCount else { return [] }
        return Array(parent.pathComponents.dropFirst(rootCount)).filter { $0 != "/" }
    }

    private func ensureLoaded(_ node: TreeNode) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            node.loadChildrenIfNeeded { continuation.resume() }
        }
    }

    private func confirmUnsavedChanges() -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "Unsaved changes"
        alert.informativeText = "The document has unsaved changes. Save them before switching?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal()
    }

    // MARK: Editor

    func editSelectedFile() {
        guard let url = selectedURL, isSelectionEditable else { return }
        if activeDocument?.url == url {
            paneMode = .editor
            return
        }
        let doc = TextDocument(url: url)
        doc.load()
        activeDocument = doc
        paneMode = .editor
    }

    func showPreview() {
        paneMode = .preview
    }

    func toggleEditPreview() {
        if paneMode == .editor {
            showPreview()
        } else {
            editSelectedFile()
        }
    }

    func saveActiveDocument() {
        guard let doc = activeDocument, doc.isDirty else { return }
        do {
            try doc.save()
        } catch {
            activeAlert = AlertItem(title: "Save", message: error.localizedDescription)
        }
    }

    // MARK: New files

    func createNewMarkdownFile() { createNewFile(markdown: true) }
    func createNewTextFile() { createNewFile(markdown: false) }

    private func createNewFile(markdown: Bool) {
        let panel = NSSavePanel()
        if markdown {
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = "Untitled.md"
        } else {
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "Untitled.txt"
        }
        panel.canCreateDirectories = true
        panel.message = markdown ? "Create a new Markdown file" : "Create a new text file"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let initial = markdown ? "# New Document\n\nStart writing…\n" : ""
        do {
            try TextFileIO.write(initial, to: url)
        } catch {
            activeAlert = AlertItem(title: "New File", message: error.localizedDescription)
            return
        }

        // Make sure the file sits under a known root (add its folder if not).
        if rootFolder(containing: url) == nil {
            addFolders(urls: [url.deletingLastPathComponent()])
        }
        // Refresh the tree node that now contains the new file.
        if let root = rootFolder(containing: url) {
            treeNode(for: root).reload()
            reloadNodeIfVisible(containing: url)
        }
        revealAndSelect(url)
        // Land in the editor ready to type.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self.editSelectedFile()
        }
    }

    private func reloadNodeIfVisible(containing url: URL) {
        // Best-effort: reload cached root nodes when visible expansions exist.
        for (path, node) in nodeCache where expandedPaths.contains(path) {
            if url.path.hasPrefix(path + "/") {
                node.reload()
            }
        }
    }

    // MARK: Preview actions (toolbar + menu share these)

    func emailSelectedFile() {
        guard let url = selectedURL else { return }
        EmailService.email(url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                break
            case .failure(let error):
                if let emailError = error as? EmailService.EmailError,
                   case .outlookNeedsPermission = emailError {
                    self.presentAutomationGuidance()
                } else {
                    self.activeAlert = AlertItem(title: "Email", message: error.localizedDescription)
                }
            }
        }
    }

    /// Guides the user through granting Automation permission to Outlook,
    /// with a deep link to the exact System Settings pane and a retry.
    private func presentAutomationGuidance() {
        let alert = NSAlert()
        alert.messageText = "MotStar needs permission to email via Outlook"
        alert.informativeText = """
        To attach files with Outlook, macOS must allow MotStar to control it.

        1. Click “Open Automation Settings…”.
        2. In System Settings, find the Microsoft Outlook row and tick “MotStar”.
        3. Click “Try Again”.
        """
        alert.addButton(withTitle: "Open Automation Settings…")
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            emailSelectedFile()
        default:
            break
        }
    }

    func printSelectedFile() {
        guard let url = selectedURL else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await PrintExportService.print(url,
                                                   draftText: draftTextForSelection,
                                                   wikilinkRoots: roots.map(\.url))
            } catch {
                activeAlert = AlertItem(title: "Print", message: error.localizedDescription)
            }
        }
    }

    func exportSelectedFileAsPDF() {
        guard let url = selectedURL else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let data = try await PrintExportService.pdfData(for: url,
                                                                draftText: draftTextForSelection,
                                                                wikilinkRoots: roots.map(\.url))
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + ".pdf"
                panel.canCreateDirectories = true
                let response = panel.runModal()
                guard response == .OK, let destination = panel.url else { return }
                try data.write(to: destination, options: .atomic)
            } catch {
                activeAlert = AlertItem(title: "Export PDF", message: error.localizedDescription)
            }
        }
    }

    /// Exports the selected Markdown/text file as a self-contained HTML
    /// document (all styles and renderers inlined, images embedded).
    func exportSelectedFileAsHTML() {
        guard let url = selectedURL, let kind = selectedKind,
              Self.isEditable(kind) else { return }

        let html: String
        if kind == .markdown {
            let text = draftTextForSelection ?? MarkdownHTML.readText(url) ?? ""
            html = MarkdownHTML.document(markdown: text,
                                         baseDirectory: url.deletingLastPathComponent(),
                                         wikilinkRoots: roots.map(\.url))
        } else {
            let text = draftTextForSelection ?? TextFileIO.read(url) ?? ""
            html = TextHTML.document(text: text)
        }

        isWorking = true
        Task {
            defer { isWorking = false }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.html]
            panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + ".html"
            panel.canCreateDirectories = true
            let response = panel.runModal()
            guard response == .OK, let destination = panel.url else { return }
            do {
                try html.write(to: destination, atomically: true, encoding: .utf8)
                let alert = NSAlert()
                alert.messageText = "HTML exported"
                alert.informativeText = "Saved to \(destination.lastPathComponent). Open it in a browser?"
                alert.addButton(withTitle: "Open in Browser")
                alert.addButton(withTitle: "Done")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(destination)
                }
            } catch {
                activeAlert = AlertItem(title: "Export HTML", message: error.localizedDescription)
            }
        }
    }

    func shareSelectedFile() {
        guard let url = selectedURL else { return }
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow, let content = window.contentView {
            let anchor = NSRect(x: content.bounds.midX, y: content.bounds.midY, width: 0, height: 0)
            picker.show(relativeTo: anchor, of: content, preferredEdge: .minY)
        }
    }

    func toggleMarkdownDisplay() {
        markdownDisplayMode = markdownDisplayMode == .formatted ? .raw : .formatted
    }

    // MARK: Focus mode & word wrap

    func toggleFocusMode() {
        isFocusMode.toggle()
    }

    func toggleWordWrap() {
        wordWrapEnabled.toggle()
        if let textView = activeEditorTextView {
            applyWrap(textView)
        }
    }

    func applyWrap(_ textView: NSTextView) {
        textView.isHorizontallyResizable = !wordWrapEnabled
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = wordWrapEnabled
        textView.textContainer?.containerSize = NSSize(
            width: wordWrapEnabled ? textView.frame.width : .greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude)
        textView.needsLayout = true
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    }

    // MARK: Markdown editing formats

    enum MarkdownFormat {
        case heading(level: Int)
        case bold
        case italic
        case inlineCode
        case blockquote
        case bulletList
        case numberedList
        case link
        case image
    }

    func applyMarkdownFormat(_ format: MarkdownFormat) {
        guard let textView = activeEditorTextView else { return }
        let text = textView.string as NSString
        let selected = textView.selectedRange()
        let safeLocation = min(selected.location, text.length)
        let selection = text.length > safeLocation
            ? text.substring(with: NSRange(location: safeLocation, length: min(selected.length, text.length - safeLocation)))
            : ""

        func lineStartRange() -> NSRange {
            let range = text.lineRange(for: NSRange(location: safeLocation, length: 0))
            return NSRange(location: range.location, length: 0)
        }

        func wrap(selection: String, prefix: String, suffix: String, placeholder: String) {
            let content = selection.isEmpty ? placeholder : selection
            let insert = prefix + content + suffix
            textView.insertText(insert, replacementRange: textView.selectedRange())
            if selection.isEmpty {
                // Place the caret inside the placeholder content.
                let caret = NSRange(location: textView.selectedRange().location - suffix.count - content.count,
                                    length: content.count)
                textView.setSelectedRange(caret)
            }
        }

        switch format {
        case .heading(let level):
            let marker = String(repeating: "#", count: max(1, min(level, 6))) + " "
            textView.insertText(marker, replacementRange: lineStartRange())
        case .bold:
            wrap(selection: selection, prefix: "**", suffix: "**", placeholder: "bold text")
        case .italic:
            wrap(selection: selection, prefix: "*", suffix: "*", placeholder: "italic text")
        case .inlineCode:
            wrap(selection: selection, prefix: "`", suffix: "`", placeholder: "code")
        case .blockquote:
            textView.insertText("> ", replacementRange: lineStartRange())
        case .bulletList:
            textView.insertText("- ", replacementRange: lineStartRange())
        case .numberedList:
            textView.insertText("1. ", replacementRange: lineStartRange())
        case .link:
            insertFileLinkIntoEditor(selection: selection)
        case .image:
            insertImageIntoEditor(selection: selection)
        }
    }

    // MARK: Insert file/image via open panel

    /// Inserts `![alt](path)` choosing the image with a native open panel
    /// (searchable/browsable). Paths inside the document folder are inserted
    /// relative to it (Obsidian-style); others fall back to an absolute path
    /// which the renderer embeds inline.
    private func insertImageIntoEditor(selection: String) {
        guard let document = activeDocument else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image to insert into “\(document.url.lastPathComponent)”"
        panel.prompt = "Insert Image"
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        let alt = selection.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : selection
        let path = insertedPath(for: fileURL, relativeTo: document.url.deletingLastPathComponent())
        insertMarkdown("![\(alt)](\(path))")
    }

    /// Inserts `[text](path)` choosing any file with a native open panel.
    private func insertFileLinkIntoEditor(selection: String) {
        guard let document = activeDocument else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a file to link from “\(document.url.lastPathComponent)”"
        panel.prompt = "Insert Link"
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        let label = selection.isEmpty ? fileURL.lastPathComponent : selection
        let path = insertedPath(for: fileURL, relativeTo: document.url.deletingLastPathComponent())
        insertMarkdown("[\(label)](\(path))")
    }

    /// Relative to the document folder when possible, else the absolute path.
    private func insertedPath(for fileURL: URL, relativeTo base: URL) -> String {
        let filePath = fileURL.path
        let basePath = base.path
        if filePath.hasPrefix(basePath + "/") {
            let relative = String(filePath.dropFirst(basePath.count + 1))
            let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
            return encoded
        }
        let encoded = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileURL.path
        return encoded
    }

    private func insertMarkdown(_ text: String) {
        guard let textView = activeEditorTextView else { return }
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    // MARK: Sidebar file search (quick-find by name)

    /// A file matched by the sidebar quick-find.
    struct SearchHit: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
        let parentName: String
    }

    @Published var searchQuery = ""
    @Published var searchResults: [SearchHit] = []
    @Published var searchTruncated = false
    @Published var searchOpen = false
    /// Increment to ask the sidebar to focus its search field.
    @Published var searchFocusRequest = 0

    private var searchTask: Task<Void, Never>?

    var isSearching: Bool { !searchQuery.isEmpty }

    func startSearch() {
        searchOpen = true
        searchFocusRequest += 1
    }

    func setSearchQuery(_ query: String) {
        searchQuery = query
        scheduleSearch()
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        searchTruncated = false
    }

    func selectSearchHit(_ hit: SearchHit) {
        clearSearch()
        revealAndSelect(hit.url)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchTruncated = false
            return
        }
        let rootURLs = roots.map(\.url)
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // debounce typing
            guard !Task.isCancelled else { return }
            let scan = await Task.detached(priority: .userInitiated) {
                Self.scan(query: query, roots: rootURLs, limit: 250)
            }.value
            guard !Task.isCancelled, let self,
                  self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            self.searchResults = scan.hits
            self.searchTruncated = scan.truncated
        }
        searchTask = task
    }

    /// Recursive name search over the root folders (background). Hidden files
    /// and package internals are skipped; folders are traversed but not
    /// reported (files only). Returns up to `limit` hits.
    nonisolated private static func scan(query: String, roots: [URL], limit: Int) -> (hits: [SearchHit], truncated: Bool) {
        var hits: [SearchHit] = []
        var truncated = false
        let fileManager = FileManager.default

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if hits.count >= limit {
                    truncated = true
                    break
                }
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard !isDirectory else { continue }
                let name = url.lastPathComponent
                guard name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
                hits.append(SearchHit(url: url,
                                      name: name,
                                      parentName: url.deletingLastPathComponent().lastPathComponent))
            }
            if hits.count >= limit {
                truncated = true
                break
            }
        }
        return (hits.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, truncated)
    }

    // MARK: Private

    private func persistAndRebuild() {
        persistence.save(roots)
        rebuildRootNodes()
        watcher?.update(paths: roots.map(\.path))
    }

    private func rebuildRootNodes() {
        let livePaths = Set(roots.map(\.path))
        nodeCache = nodeCache.filter { livePaths.contains($0.key) }
        rootNodes = roots.map { treeNode(for: $0) }
    }
}
