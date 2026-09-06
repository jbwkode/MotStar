import Foundation

/// Directory scanning for the tree (ADR-006): hidden items excluded, folders
/// always sorted alphabetically first, then files ordered per the user's
/// `FileSortMode` preference (newest-first by default, or alphabetical).
/// Missing folders return an error state instead of throwing so an
/// unavailable folder degrades gracefully.
enum FolderEnumerator {

    struct Result {
        var children: [TreeNode] = []
        var error: String?
    }

    private struct Item {
        let url: URL
        let isFolder: Bool
        let name: String
        let modified: Date?
    }

    static func children(of url: URL) -> Result {
        var result = Result()

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            result.error = "Folder is unavailable"
            return result
        }
        guard isDir.boolValue else {
            result.error = "Not a folder"
            return result
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            result.error = "Cannot read folder"
            return result
        }

        var entries: [Item] = []
        for item in items {
            guard !item.lastPathComponent.hasPrefix(".") else { continue } // hidden files (.git, .DS_Store…)
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            entries.append(Item(
                url: item,
                isFolder: values?.isDirectory ?? item.hasDirectoryPath,
                name: item.lastPathComponent,
                modified: values?.contentModificationDate
            ))
        }

        entries.sort { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder } // folders first
            if lhs.isFolder {
                // Folders: always alphabetical.
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            // Files: configurable — newest first (default) or alphabetical.
            switch FileSortMode.current {
            case .newestFirst:
                switch (lhs.modified, rhs.modified) {
                case let (l?, r?):
                    if l != r { return l > r }
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            case .alphabetical:
                break
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        result.children = entries.map { TreeNode(url: $0.url) }
        return result
    }
}
