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
            ToolbarItem(placement: .principal) {
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

/// MotStar brand glyph + name in the window title bar. The glyph (star
/// outline + M) is a transparent template image so it adapts to light/dark.
private struct BrandHeader: View {
    private static let brandMark: NSImage? = {
        let candidates = [
            Bundle.main.url(forResource: "BrandMark", withExtension: "png"),
            Bundle.module.url(forResource: "BrandMark", withExtension: "png")
        ]
        for url in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }()

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let image = Self.brandMark {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.primary)
                } else if let image = MotStarAssets.loadLogo() {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "star.circle.fill")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(height: 16)

            Text("MotStar")
                .font(.system(size: 13, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MotStar")
    }
}
