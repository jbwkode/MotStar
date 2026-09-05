import Foundation
import UniformTypeIdentifiers

/// Central file-type registry — single source of truth for marker colour,
/// conventional icon and preview strategy (see ADR-007 and design doc §5.3).
enum FileKind: String, CaseIterable {
    case folder
    case markdown
    case text
    case pdf
    case docx
    case pptx
    case xlsx
    case image
    case other

    // MARK: Marker colour (RGB 0...1)

    /// Returns nil for folders (no marker dot — folders use the folder icon).
    var markerRGB: (red: Double, green: Double, blue: Double)? {
        switch self {
        case .folder: return nil
        case .markdown: return (0.388, 0.396, 0.945)   // Indigo #6366F1
        case .text, .other: return (0.612, 0.639, 0.686) // Grey #9CA3AF
        case .pdf: return (0.898, 0.243, 0.243)        // Red #E53E3E
        case .docx: return (0.169, 0.341, 0.604)       // Word blue #2B579A
        case .pptx: return (0.824, 0.278, 0.149)       // PowerPoint orange #D24726
        case .xlsx: return (0.129, 0.451, 0.275)       // Excel green #217346
        case .image: return (0.024, 0.714, 0.831)      // Cyan #06B6D4
        }
    }

    /// Conventional macOS SF Symbol for the file/folder type.
    var symbolName: String {
        switch self {
        case .folder: return "folder.fill"
        case .markdown: return "doc.richtext"
        case .text: return "doc.plaintext"
        case .pdf: return "doc.richtext"
        case .docx: return "doc.text"
        case .pptx: return "chart.bar.doc.horizontal"
        case .xlsx: return "tablecells"
        case .image: return "photo"
        case .other: return "doc"
        }
    }
}

enum FileTypeRegistry {

    /// Classify a file system item. Case-insensitive extension first,
    /// UTI check as fallback; unknown files become `.other` (ADR-007, Q3).
    static func kind(for url: URL, isFolder: Bool) -> FileKind {
        if isFolder { return .folder }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "markdown": return .markdown
        case "txt": return .text
        case "pdf": return .pdf
        case "docx": return .docx
        case "pptx": return .pptx
        case "xlsx": return .xlsx
        case "jpg", "jpeg", "png": return .image
        default: break
        }

        // UTI fallback (handles unusual casing / extended attributes).
        if let uti = UTType(filenameExtension: ext) {
            if uti.conforms(to: .pdf) { return .pdf }
            if uti.conforms(to: .plainText) { return .text }
            if uti.conforms(to: .image) { return .image }
            if uti.conforms(to: .presentation) { return .pptx }
            if uti.conforms(to: .spreadsheet) { return .xlsx }
            if uti.conforms(to: .text) { return .text }
        }
        return .other
    }

    static func kind(for url: URL) -> FileKind {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        return kind(for: url, isFolder: isDir)
    }
}
