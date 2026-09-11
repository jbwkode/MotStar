import Foundation
import Combine

/// An in-memory editable text/markdown document bound to one file URL.
/// Tracks unsaved changes against the snapshot loaded from disk.
@MainActor
final class TextDocument: ObservableObject {
    let url: URL

    @Published var text: String = "" {
        didSet { isDirty = (text != loadedSnapshot) }
    }
    @Published private(set) var loadedSnapshot = ""
    @Published private(set) var isDirty = false
    @Published var loadFailed = false

    /// Bumped whenever `text` is replaced from disk (load/revert). Views can
    /// use this to distinguish a real reload from a user edit and reset any
    /// cached state (e.g. the source editor's undo history).
    @Published private(set) var revision = 0

    init(url: URL) {
        self.url = url
    }

    func load() {
        if let content = TextFileIO.read(url) {
            text = content
            loadedSnapshot = content
            isDirty = false
            loadFailed = false
            revision += 1
        } else {
            loadFailed = true
        }
    }

    /// Abandons unsaved edits by re-reading the file from disk. If the file
    /// cannot be read the draft is kept (and stays dirty) so no work is lost.
    /// Uses `load()`, so a missing/unreadable file leaves the document intact.
    func revert() {
        load()
    }

    /// Writes the current draft to disk and updates the clean snapshot.
    func save() throws {
        try TextFileIO.write(text, to: url)
        loadedSnapshot = text
        isDirty = false
    }
}
