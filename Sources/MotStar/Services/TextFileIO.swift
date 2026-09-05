import Foundation

/// Small, shared text file helpers used by the editor, preview and export.
enum TextFileIO {

    /// Reads a text file, trying common encodings (UTF-8, UTF-16, Latin-1).
    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
    }

    static func write(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: .atomic)
    }
}
