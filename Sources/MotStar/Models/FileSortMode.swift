import Foundation

/// How files (not folders) are ordered in the tree.
enum FileSortMode: String, CaseIterable, Identifiable {
    case newestFirst
    case alphabetical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: return "Newest first"
        case .alphabetical: return "Alphabetical (A–Z)"
        }
    }

    static let storageKey = "motstar.filesort"

    /// Current preference read from UserDefaults. Safe to call on any thread
    /// (background tree enumeration reads it directly).
    static var current: FileSortMode {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return .newestFirst }
        return FileSortMode(rawValue: raw) ?? .newestFirst
    }
}
