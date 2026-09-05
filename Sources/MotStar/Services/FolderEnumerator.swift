import Foundation

/// Directory scanning for the tree (ADR-006): hidden items excluded, sorted
/// folders-first then files, localized case-insensitive, error instead of
/// throwing so an unavailable folder degrades gracefully.
enum FolderEnumerator {

    struct Result {
        var children: [TreeNode] = []
        var error: String?
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

        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            result.error = "Cannot read folder"
            return result
        }

        for item in items {
            guard !item.lastPathComponent.hasPrefix(".") else { continue } // hidden files (.git, .DS_Store…)
            result.children.append(TreeNode(url: item))
        }

        result.children.sort { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return result
    }
}
