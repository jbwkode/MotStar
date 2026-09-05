import Foundation

/// One folder or file in the tree. Children are loaded lazily, only when the
/// user expands the node (ADR-006): `children == nil` means "not yet loaded".
final class TreeNode: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let name: String
    let isFolder: Bool

    @Published private(set) var children: [TreeNode]?
    @Published var loadError: String?

    private var hasStartedLoading = false

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        self.isFolder = isDir
    }

    var kind: FileKind { FileTypeRegistry.kind(for: url, isFolder: isFolder) }

    var isLoaded: Bool { children != nil }

    /// Safe to call repeatedly; loads at most once per node. The optional
    /// completion runs on the main actor once children (or an error) land.
    func loadChildrenIfNeeded(completion: (() -> Void)? = nil) {
        guard isFolder else {
            completion?()
            return
        }
        if hasStartedLoading {
            if isLoaded || loadError != nil {
                completion?()
            } else {
                pendingCompletions.append(completion ?? {})
            }
            return
        }
        hasStartedLoading = true
        if let completion {
            pendingCompletions.append(completion)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = FolderEnumerator.children(of: self.url)
            DispatchQueue.main.async {
                self.loadError = result.error
                self.children = result.children
                let pending = self.pendingCompletions
                self.pendingCompletions.removeAll()
                pending.forEach { $0() }
            }
        }
    }

    private var pendingCompletions: [() -> Void] = []

    /// Forgets loaded children so the next expansion re-reads the folder
    /// (used after creating files so the tree reflects the change).
    func reload() {
        children = nil
        loadError = nil
        hasStartedLoading = false
        pendingCompletions.removeAll()
    }

    /// True when children have loaded or the load failed (no spinner needed).
    var isSettled: Bool { isLoaded || loadError != nil }
}
