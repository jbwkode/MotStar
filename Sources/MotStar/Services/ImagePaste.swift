import AppKit
import Foundation

/// Pulls image data off the pasteboard and stores it next to the document
/// being edited, so pasted screenshots don't depend on the clipboard.
enum ClipboardImage {

    /// Cheap check used by menu validation — no TIFF decoding on every
    /// keystroke. True when the pasteboard carries an image we can save.
    static func hasImage(on pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.availableType(from: [.png, .tiff]) != nil
            || pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    /// PNG bytes for the pasteboard's image, if it has one. TIFF (and any
    /// other `NSImage`-representable flavor) is converted to PNG.
    static func pngData(from pasteboard: NSPasteboard = .general) -> Data? {
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }
}

/// Writes pasted images into an `images/` folder beside the document.
enum ImagePasteStore {

    /// Folder name created/used next to the Markdown file.
    static let folderName = "images"

    /// Saves `data` as `<images>/image-<timestamp>.png` beside `documentURL`
    /// and returns the path to insert into the Markdown source, relative to
    /// the document folder (e.g. `images/image-2026-10-30-125730.png`).
    @discardableResult
    static func save(_ data: Data,
                     beside documentURL: URL,
                     now: Date = Date()) throws -> String {
        let directory = documentURL
            .deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let name = uniqueName(base: "image-\(timestamp(now))",
                              fileExtension: "png",
                              in: directory)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return "\(folderName)/\(name)"
    }

    /// `yyyy-MM-dd-HHmmss` in the local time zone — readable in a file listing
    /// and sorts chronologically.
    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    /// Same-second pastes would collide; suffix `-2`, `-3`, … instead of
    /// overwriting an image that the document already references.
    private static func uniqueName(base: String, fileExtension: String, in directory: URL) -> String {
        var candidate = "\(base).\(fileExtension)"
        var counter = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(counter).\(fileExtension)"
            counter += 1
        }
        return candidate
    }
}
