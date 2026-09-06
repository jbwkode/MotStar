import SwiftUI
import UniformTypeIdentifiers

/// Main two-pane window (FR-2): sidebar tree on the left, preview on the right.
/// Focus mode collapses the sidebar for distraction-free editing.
struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    private var visibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { app.isFocusMode ? .detailOnly : .all },
            set: { _ in }
        )
    }

    /// Trailing outline pane: shown for Markdown in the editor or a formatted
    /// preview. The binding is read-only on collapse — `showOutline` stays
    /// true so re-opening happens when the user returns to Markdown.
    private var outlineBinding: Binding<Bool> {
        Binding(
            get: { app.showOutline && app.outlineIsApplicable },
            set: { app.showOutline = $0 }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: visibility) {
            SidebarView()
        } detail: {
            PreviewPane()
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: outlineBinding) {
            OutlinePane()
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AppIconMark()
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .fileImporter(
            isPresented: $app.showAddFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                app.addFolders(urls: urls)
            case .failure:
                break // user cancelled or picker failed — no-op
            }
        }
    }
}

/// The app icon shown at the right-hand side of the title bar. Clicking it
/// minimizes the app window to the Dock.
private struct AppIconMark: View {
    var body: some View {
        Button {
            NSApp.keyWindow?.miniaturize(nil)
        } label: {
            Group {
                if let image = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Minimize MotStar")
        .accessibilityLabel("Minimize MotStar")
    }
}
