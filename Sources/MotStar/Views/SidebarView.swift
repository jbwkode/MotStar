import SwiftUI

/// Left pane: root folders as a recursive, lazy tree plus "Add Folder…".
/// A quick-find field (⌘F) filters files by name across all root folders.
/// Expansion state lives in `AppState` so menu actions can expand the tree
/// programmatically (FR-3, FR-4, ADR-006).
struct SidebarView: View {
    @EnvironmentObject private var app: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if app.isSearching {
                searchResultsList
            } else {
                treeList
            }
            Divider()
            addFolderButton
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        .onChange(of: app.searchFocusRequest) { _, _ in
            searchFocused = app.searchOpen
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find files…", text: Binding(
                get: { app.searchQuery },
                set: { app.setSearchQuery($0) }
            ))
            .textFieldStyle(.plain)
            .focused($searchFocused)
            .onExitCommand { app.clearSearch() }

            if !app.searchQuery.isEmpty {
                Button {
                    app.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Tree (default view)

    private var treeList: some View {
        List {
            if app.rootNodes.isEmpty {
                Text("No folders yet.\nClick Add Folder… to choose folders from storage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(app.rootNodes) { node in
                if let root = app.roots.first(where: { $0.path == node.url.path }) {
                    FolderDisclosure(node: node)
                        .contextMenu {
                            Button(role: .destructive) {
                                app.remove(root)
                            } label: {
                                Label("Remove “\(root.name)”", systemImage: "minus.circle")
                            }
                        }
                } else {
                    FolderDisclosure(node: node)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Search results (flat, cross-folder)

    private var searchResultsList: some View {
        List {
            if app.searchResults.isEmpty {
                Text("No files matching “\(app.searchQuery)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(app.searchResults) { hit in
                    SearchResultRow(hit: hit)
                }
                if app.searchTruncated {
                    Text("Showing first 250 matches")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var addFolderButton: some View {
        HStack(spacing: 4) {
            Button {
                app.showAddFolder = true
            } label: {
                Label("Add Folder…", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(6)
    }
}

/// One quick-find result row: marker + icon + name, with the parent folder
/// as a secondary caption. Selecting reveals and opens the file in the tree.
struct SearchResultRow: View {
    @EnvironmentObject private var app: AppState
    let hit: AppState.SearchHit

    private var kind: FileKind { FileTypeRegistry.kind(for: hit.url) }

    var body: some View {
        Button {
            app.selectSearchHit(hit)
        } label: {
            HStack(spacing: 7) {
                if let rgb = kind.markerRGB {
                    Circle()
                        .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                        .frame(width: 9, height: 9)
                }
                Image(systemName: kind.symbolName)
                    .foregroundStyle(kind.markerColor ?? .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("in \(hit.parentName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A folder row that expands into a recursive sub-tree, loading children only
/// on first expansion (ADR-006). Expansion state lives in `AppState`.
struct FolderDisclosure: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var node: TreeNode

    private var path: String { node.url.path }

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { app.isExpanded(path) },
                set: { app.setExpanded(path, $0) }
            )
        ) {
            content
        } label: {
            rowLabel
        }
    }

    @ViewBuilder private var content: some View {
        if node.isLoaded {
            if let children = node.children, !children.isEmpty {
                ForEach(children) { child in
                    if child.isFolder {
                        FolderDisclosure(node: child)
                    } else {
                        FileRow(node: child)
                    }
                }
            } else {
                Text("Empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if node.loadError != nil {
            Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            ProgressView()
                .controlSize(.small)
                .onAppear { node.loadChildrenIfNeeded() }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: node.kind.symbolName)
                .foregroundStyle(.tint)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(node.loadError == nil ? .primary : .secondary)
        }
        .padding(.vertical, 1)
    }
}

/// A file row: colour marker + conventional icon + name (FR-6, FR-7).
/// Selecting a row previews the file in the right pane (FR-8); Markdown/text
/// files can then be edited via the Edit/Preview toggle.
struct FileRow: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var node: TreeNode

    private var isSelected: Bool { app.selectedURL == node.url }

    var body: some View {
        Button {
            app.selectFile(node.url)
        } label: {
            HStack(spacing: 7) {
                marker
                Image(systemName: node.kind.symbolName)
                    .foregroundStyle(node.kind.markerColor ?? .secondary)
                    .frame(width: 16)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.18))
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var marker: some View {
        if let rgb = node.kind.markerRGB {
            Circle()
                .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                .frame(width: 9, height: 9)
        } else {
            Color.clear.frame(width: 9, height: 9)
        }
    }
}

extension FileKind {
    /// Marker colour as a SwiftUI Color (nil for folders).
    var markerColor: Color? {
        guard let rgb = markerRGB else { return nil }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
