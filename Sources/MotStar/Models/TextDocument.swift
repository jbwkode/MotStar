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

    init(url: URL) {
        self.url = url
    }

    func load() {
        if let content = TextFileIO.read(url) {
            text = content
            loadedSnapshot = content
            isDirty = false
            loadFailed = false
        } else {
            loadFailed = true
        }
    }

    /// Writes the current draft to disk and updates the clean snapshot.
    func save() throws {
        try TextFileIO.write(text, to: url)
        loadedSnapshot = text
        isDirty = false
    }
}
