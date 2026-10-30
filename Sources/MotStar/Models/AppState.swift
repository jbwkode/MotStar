import Foundation
import Combine
import AppKit
import WebKit
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
    @Published var activeDocument: TextDocument? {
        didSet { bindOutlineToDocument() }
    }
    @Published var activeAlert: AlertItem?
    @Published var isWorking = false
    @Published var isFocusMode = false
    @Published var wordWrapEnabled = true
    @Published var showOutline = false
    @Published var outlineHeadings: [OutlineHeading] = []
    @Published var readingFontSize: Double {
        didSet { UserDefaults.standard.set(readingFontSize, forKey: Self.readingFontKey) }
    }
    @Published var editorFontSize: Double {
        didSet { UserDefaults.standard.set(editorFontSize, forKey: Self.editorFontKey) }
    }

    /// Weak reference to the live source editor text view (set by
    /// `SourceEditorView`) so markdown-format commands can act on the
    /// current selection.
    weak var activeEditorTextView: NSTextView?

    /// The formatted preview's WKWebView (set by `FormattedMarkdownView`) so
    /// outline clicks can scroll the rendered page to a heading.
    weak var previewWebView: WKWebView?

    private let persistence = PersistenceService()
    /// Keeps TreeNode instances stable per path so expansion state survives
    /// list rebuilds and folder removals.
    private var nodeCache: [String: TreeNode] = [:]
    /// Live folder watching (FSEvents) keeps the tree fresh on external edits.
    private var watcher: FolderWatcher?
    private var pendingExternalReload: DispatchWorkItem?
    /// Combine subscription keeping the outline in sync with editor typing.
    private var outlineCancellables: Set<AnyCancellable> = []

    /// Folder path the user last navigated to (selected file's folder, an
    /// expanded folder, or a newly added root). Persisted so new files land
    /// there in later sessions too.
    private var lastVisitedDirectoryPath: String? {
        didSet {
            guard let path = lastVisitedDirectoryPath else { return }
            UserDefaults.standard.set(path, forKey: Self.lastDirectoryKey)
        }
    }

    static let readingFontKey = "motstar.readingFontSize"
    static let editorFontKey = "motstar.editorFontSize"
    /// Folder the user last navigated to (sidebar selection or expansion), so
    /// the new-file panel can open there.
    static let lastDirectoryKey = "motstar.lastVisitedDirectory"
    static let defaultReadingFontSize: Double = 15
    static let defaultEditorFontSize: Double = 13
    private static let fontRange: ClosedRange<Double> = 9...30

    init() {
        readingFontSize = Self.loadFontSize(key: Self.readingFontKey, fallback: Self.defaultReadingFontSize)
        editorFontSize = Self.loadFontSize(key: Self.editorFontKey, fallback: Self.defaultEditorFontSize)
        lastVisitedDirectoryPath = UserDefaults.standard.string(forKey: Self.lastDirectoryKey)
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

    /// Reads a persisted font size, clamping to the sane range; 0 (absent)
    /// falls back to the default.
    private static func loadFontSize(key: String, fallback: Double) -> Double {
        let value = UserDefaults.standard.double(forKey: key)
        guard value >= fontRange.lowerBound, value <= fontRange.upperBound else { return fallback }
        return value
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
        kind == .markdown || kind == .text || kind == .code
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
        var firstAdded: URL?
        for url in urls {
            let path = url.path
            guard !roots.contains(where: { $0.path == path }) else { continue }
            roots.append(RootFolder(path: path))
            if firstAdded == nil { firstAdded = url }
            changed = true
        }
        guard changed else { return }
        if let first = firstAdded { rememberDirectory(first) }
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
            rememberDirectory(URL(fileURLWithPath: path))
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
        rememberDirectory(url)
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

    private func confirmUnsavedChanges(before action: String = "switching") -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "Unsaved changes"
        alert.informativeText = "The document has unsaved changes. Save them before \(action)?"
        alert.alertStyle = .warning
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

    /// Returns to the preview. When the editor holds unsaved changes, asks
    /// whether to **Save** them, **Discard** them (reload from disk) or
    /// **Cancel** and stay in the editor.
    func showPreview() {
        if let doc = activeDocument, doc.isDirty {
            switch confirmUnsavedChanges(before: "leaving the editor") {
            case .alertFirstButtonReturn: // Save
                do { try doc.save() } catch {
                    activeAlert = AlertItem(title: "Save", message: error.localizedDescription)
                    return
                }
            case .alertSecondButtonReturn: // Discard
                doc.revert()
            default: // Cancel — stay in the editor
                // Nudge SwiftUI so the segmented mode picker snaps back to
                // "Edit" even though `paneMode` never changed.
                objectWillChange.send()
                return
            }
        }
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

    /// Abandons unsaved editor changes by re-reading the file from disk.
    /// Asks for confirmation first (the discarded draft is not recoverable),
    /// then leaves the document open in its current pane. If the file cannot
    /// be re-read, the draft is kept so no work is silently lost.
    func revertActiveDocument(confirm: Bool = true) {
        guard let doc = activeDocument, doc.isDirty else { return }
        if confirm {
            let alert = NSAlert()
            alert.messageText = "Discard unsaved changes?"
            alert.informativeText = "“\(doc.url.lastPathComponent)” will be reloaded from disk. Your unsaved changes cannot be recovered."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Discard Changes")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        doc.revert()
    }

    // MARK: New files

    /// Folder the new-file panel opens in: wherever the user last navigated
    /// (a selected file's folder, an expanded folder, an added root), then the
    /// current selection, the open document's folder, and finally the first
    /// root folder. `nil` lets AppKit pick its own default.
    var preferredNewFileDirectory: URL? {
        if let path = lastVisitedDirectoryPath {
            let remembered = URL(fileURLWithPath: path)
            if isDirectory(remembered) { return remembered }
        }
        if let selected = selectedURL {
            let folder = isDirectory(selected) ? selected : selected.deletingLastPathComponent()
            if isDirectory(folder) { return folder }
        }
        if let doc = activeDocument {
            let folder = doc.url.deletingLastPathComponent()
            if isDirectory(folder) { return folder }
        }
        if let root = roots.first, root.isReachable {
            return root.url
        }
        return nil
    }

    /// Records the folder a navigation event landed in, so the next new file
    /// starts there. Files contribute their containing folder.
    private func rememberDirectory(_ url: URL) {
        let folder = isDirectory(url) ? url : url.deletingLastPathComponent()
        guard isDirectory(folder) else { return }
        lastVisitedDirectoryPath = folder.path
    }

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
        // Start in the folder the user was last working in.
        panel.directoryURL = preferredNewFileDirectory

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

    // MARK: Rename / move to trash / move / reveal

    /// Root folders are the workspace containers: rename/trash would move the
    /// vault itself, so only remove them from the list (see `remove(_:)`).
    private func isRootPath(_ path: String) -> Bool {
        roots.contains { $0.path == path }
    }

    func renameItem(_ node: TreeNode) {
        renameFile(at: node.url)
    }

    func trashItem(_ node: TreeNode) {
        trashFile(at: node.url)
    }

    func moveItem(_ node: TreeNode) {
        moveFile(at: node.url)
    }

    func revealInFinder(_ node: TreeNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    /// Menu-command entry points operate on the sidebar selection (a file).
    func renameSelectedItem() {
        guard let url = selectedURL else { return }
        renameFile(at: url)
    }

    func trashSelectedItem() {
        guard let url = selectedURL else { return }
        trashFile(at: url)
    }

    func moveSelectedItem() {
        guard let url = selectedURL else { return }
        moveFile(at: url)
    }

    private func renameFile(at oldURL: URL) {
        guard !isRootPath(oldURL.path) else { return }
        // containerPrefix also guards documents nested inside a renamed folder.
        guard resolveUnsavedDocument(for: oldURL, containerPrefix: true, title: "Rename") else { return }

        let isFolder = (try? oldURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard let newName = promptNewName(for: oldURL, isFolder: isFolder) else { return }
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        guard newURL != oldURL else { return }
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            presentError(title: "Rename",
                         message: "An item named “\(newName)” already exists in this folder.")
            return
        }

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            presentError(title: "Rename", message: error.localizedDescription)
            return
        }

        relocateDocumentState(from: oldURL, to: newURL)
        if isFolder {
            expandedPaths = remappedExpandedPaths(from: oldURL.path, to: newURL.path)
        }
        refreshTreeAndReveal(oldURL: oldURL, newURL: newURL)
    }

    private func trashFile(at url: URL) {
        guard !isRootPath(url.path) else { return }
        guard resolveUnsavedDocument(for: url, containerPrefix: true, title: "Move to Trash") else { return }

        let alert = NSAlert()
        alert.messageText = "Move “\(url.lastPathComponent)” to Trash?"
        alert.informativeText = isDirectory(url)
            ? "The folder and everything in it will be moved to the Trash. You can recover it from there."
            : "The file will be moved to the Trash. You can recover it from there."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            presentError(title: "Move to Trash", message: error.localizedDescription)
            return
        }

        // Anything open or selected beneath the trashed item is gone.
        if let doc = activeDocument, isUnder(doc.url, container: url) {
            activeDocument = nil
        }
        if let selected = selectedURL, isUnder(selected, container: url) {
            selectedURL = nil
        }
        expandedPaths = expandedPaths.filter { !isUnder(URL(fileURLWithPath: $0), container: url) }
        reloadNodeIfVisible(containing: url)
    }

    private func moveFile(at url: URL) {
        guard !isRootPath(url.path) else { return }
        guard resolveUnsavedDocument(for: url, containerPrefix: true, title: "Move") else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Move Here"
        panel.message = "Choose a destination folder for “\(url.lastPathComponent)”"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let newURL = destination.appendingPathComponent(url.lastPathComponent)
        let sourceIsFolder = isDirectory(url)
        if newURL.deletingLastPathComponent() == url.deletingLastPathComponent() { return } // already there
        if sourceIsFolder, isUnder(destination, container: url) {
            presentError(title: "Move", message: "A folder cannot be moved into itself.")
            return
        }
        if FileManager.default.fileExists(atPath: newURL.path) {
            presentError(title: "Move",
                         message: "An item named “\(url.lastPathComponent)” already exists in the destination folder.")
            return
        }

        do {
            try moveOrCopyFallback(from: url, to: newURL)
        } catch {
            presentError(title: "Move", message: error.localizedDescription)
            return
        }

        relocateDocumentState(from: url, to: newURL)
        if sourceIsFolder {
            expandedPaths = expandedPaths.filter { !isUnder(URL(fileURLWithPath: $0), container: url) }
        }
        refreshTreeAndReveal(oldURL: url, newURL: newURL)
    }

    /// `FileManager.moveItem` fails across volumes; fall back to copy + delete.
    private func moveOrCopyFallback(from source: URL, to destination: URL) throws {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.removeItem(at: source)
        }
    }

    private func refreshTreeAndReveal(oldURL: URL, newURL: URL) {
        reloadNodeIfVisible(containing: oldURL)
        reloadNodeIfVisible(containing: newURL)
        if rootFolder(containing: newURL) != nil {
            revealAndSelect(newURL)
        } else if selectedURL == newURL {
            // Moved outside every root: keep the preview open but no tree row.
            selectedURL = newURL
        }
    }

    /// Saves or discards a dirty editor buffer for an item about to be
    /// renamed/moved/trashed. `containerPrefix` also guards documents nested
    /// inside a folder being moved/trashed. Returns false when cancelled.
    private func resolveUnsavedDocument(for url: URL, containerPrefix: Bool, title: String) -> Bool {
        guard let doc = activeDocument, doc.isDirty else { return true }
        let affectsDoc = containerPrefix
            ? isUnder(doc.url, container: url)
            : doc.url == url
        guard affectsDoc else { return true }
        switch confirmUnsavedChanges() {
        case .alertFirstButtonReturn: // Save
            do { try doc.save() } catch {
                presentError(title: title, message: error.localizedDescription)
                return false
            }
            return true
        case .alertSecondButtonReturn: // Discard
            return true
        default: // Cancel
            return false
        }
    }

    /// Keeps selection and the open editor buffer pointing at the moved item.
    private func relocateDocumentState(from oldURL: URL, to newURL: URL) {
        if let doc = activeDocument, doc.url == oldURL {
            let reopened = TextDocument(url: newURL)
            reopened.load()
            activeDocument = reopened
        } else if let doc = activeDocument, isUnder(doc.url, container: oldURL) {
            // A folder move/rename relocated an open document inside it.
            let suffix = String(doc.url.path.dropFirst(oldURL.path.count))
            let relocated = TextDocument(url: URL(fileURLWithPath: newURL.path + suffix))
            relocated.load()
            activeDocument = relocated
        }
        if selectedURL == oldURL {
            selectedURL = newURL
        } else if let selected = selectedURL, isUnder(selected, container: oldURL) {
            let suffix = String(selected.path.dropFirst(oldURL.path.count))
            selectedURL = URL(fileURLWithPath: newURL.path + suffix)
        }
    }

    private func remappedExpandedPaths(from oldPath: String, to newPath: String) -> Set<String> {
        var remapped: Set<String> = []
        for path in expandedPaths {
            if path == oldPath {
                remapped.insert(newPath)
            } else if path.hasPrefix(oldPath + "/") {
                remapped.insert(newPath + String(path.dropFirst(oldPath.count)))
            } else {
                remapped.insert(path)
            }
        }
        return remapped
    }

    private func isUnder(_ url: URL, container: URL) -> Bool {
        url.path == container.path || url.path.hasPrefix(container.path + "/")
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    /// Finder-style rename prompt: pre-fills the base name (extension kept
    /// intact), returns the full new file name or nil on cancel/no-op.
    private func promptNewName(for url: URL, isFolder: Bool) -> String? {
        let originalName = url.lastPathComponent
        let prefill: String
        if !isFolder, !url.pathExtension.isEmpty {
            prefill = url.deletingPathExtension().lastPathComponent
        } else {
            prefill = originalName
        }

        let alert = NSAlert()
        alert.messageText = "Rename “\(originalName)”"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = prefill
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        var typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, typed != ".", typed != "..", !typed.contains("/") else { return nil }
        // Keep the original extension when the user only edited the base name.
        let ext = url.pathExtension
        if !ext.isEmpty, !typed.contains(".") {
            typed += "." + ext
        }
        return typed == originalName ? nil : typed
    }

    private func presentError(title: String, message: String) {
        activeAlert = AlertItem(title: title, message: message)
    }

    // MARK: Document outline

    /// The outline pane applies to Markdown only, and only in the editor or a
    /// formatted preview (raw text and other file kinds have no anchors).
    var outlineIsApplicable: Bool {
        guard selectedKind == .markdown else { return false }
        return paneMode == .editor || markdownDisplayMode == .formatted
    }

    func toggleOutline() {
        showOutline.toggle()
        if showOutline { refreshOutline() }
    }

    /// Text the outline reflects: the live editor draft when one is open for
    /// the selection, otherwise the file on disk (matching the preview).
    private var outlineSourceText: String? {
        if let doc = activeDocument, doc.url == selectedURL {
            return doc.text
        }
        guard let url = selectedURL else { return nil }
        return MarkdownHTML.readText(url)
    }

    private func refreshOutline() {
        guard showOutline, outlineIsApplicable else {
            outlineHeadings = []
            return
        }
        outlineHeadings = MarkdownOutline.parse(outlineSourceText ?? "")
    }

    /// Keeps the outline in sync with the live draft while typing (debounced).
    private func bindOutlineToDocument() {
        outlineCancellables.removeAll()
        if let doc = activeDocument {
            doc.objectWillChange
                .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
                .sink { [weak self] _ in self?.refreshOutline() }
                .store(in: &outlineCancellables)
        }
        refreshOutline()
    }

    /// Outline click: scrolls the editor to the heading's source line, or the
    /// formatted preview to the heading element (row order matches DOM order).
    func jumpToOutlineHeading(at index: Int, line: Int) {
        if paneMode == .editor {
            scrollEditor(toLine: line)
        } else if markdownDisplayMode == .formatted {
            scrollPreview(toOutlineIndex: index)
        }
    }

    private func scrollEditor(toLine line: Int) {
        guard let textView = activeEditorTextView else { return }
        let ns = textView.string as NSString
        var idx = 0
        var current = 1
        while current < line, idx < ns.length {
            let range = ns.lineRange(for: NSRange(location: idx, length: 0))
            idx = NSMaxRange(range)
            current += 1
        }
        guard line == 1 || current == line else { return }
        let target = NSRange(location: min(idx, ns.length), length: 0)
        textView.scrollRangeToVisible(target)
        textView.setSelectedRange(target)
        textView.window?.makeFirstResponder(textView)
    }

    private func scrollPreview(toOutlineIndex index: Int) {
        guard let webView = previewWebView else { return }
        let script = """
        (function(){
          var hs = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
          if (hs[\(index)]) { hs[\(index)].scrollIntoView({block:'start'}); return true; }
          return false;
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: Text zoom (reader panes + editor)

    /// Adjusts the font size of the current context: the source editor while
    /// editing, otherwise the reading panes (formatted/raw preview).
    func zoomFont(by delta: Double) {
        if paneMode == .editor {
            editorFontSize = Self.clampFont(editorFontSize + delta)
        } else {
            readingFontSize = Self.clampFont(readingFontSize + delta)
        }
    }

    func resetFontZoom() {
        if paneMode == .editor {
            editorFontSize = Self.defaultEditorFontSize
        } else {
            readingFontSize = Self.defaultReadingFontSize
        }
    }

    private static func clampFont(_ value: Double) -> Double {
        min(max(value, fontRange.lowerBound), fontRange.upperBound)
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

    /// Pastes a clipboard image: saves it into `images/` beside the document
    /// being edited and inserts a relative link at the caret.
    ///
    /// Returns `false` when there is no editor or no image on the clipboard.
    @discardableResult
    func insertClipboardImage() -> Bool {
        (activeEditorTextView as? MarkdownEditorTextView)?.insertPastedImage() ?? false
    }

    /// Inserts `[text](path)` choosing any file with a native open panel.
    private func insertFileLinkIntoEditor(selection: String) {        guard let document = activeDocument else { return }
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
    private func insertedPath(for fileURL: URL, relativeTo base: URL) -> String {        let filePath = fileURL.path
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
