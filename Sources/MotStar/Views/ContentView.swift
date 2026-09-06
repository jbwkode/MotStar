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

    var body: some View {
        NavigationSplitView(columnVisibility: visibility) {
            SidebarView()
        } detail: {
            PreviewPane()
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                BrandHeader()
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

/// MotStar brand logo shown alone (no text) in the window title bar —
/// same artwork as the About window, transparent so it blends.
private struct BrandHeader: View {
    var body: some View {
        Group {
            if let image = MotStarAssets.loadLogo() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "star.circle.fill")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(height: 32)
        .accessibilityLabel("MotStar")
    }
}
