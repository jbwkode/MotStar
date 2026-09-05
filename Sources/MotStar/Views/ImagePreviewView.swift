import SwiftUI
import AppKit

/// Image preview for `.jpg`/`.png` (and similar) files. Images are scaled to
/// fit the pane by default so huge files always fit; double-click toggles
/// between "fit" and "actual size 1:1" (scroll to pan around the image).
struct ImagePreviewView: View {
    let url: URL

    @State private var image: NSImage?
    @State private var actualSize = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                if actualSize {
                    actualSizeView(image)
                } else {
                    fitView(image)
                }
            } else if loadFailed {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Cannot display this image.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: url) {
            image = nil
            loadFailed = false
            actualSize = false
            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
            if loaded == nil { loadFailed = true } else { image = loaded }
        }
    }

    /// Scales the image to fit entirely within the pane, preserving aspect.
    private func fitView(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { actualSize = true }
            .help("Double-click for actual size (100%)")
    }

    /// Shows the image at native pixel size inside a scroll view.
    private func actualSizeView(_ image: NSImage) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
                .resizable()
                .frame(width: image.size.width, height: image.size.height)
                .onTapGesture(count: 2) { actualSize = false }
        }
        .help("Double-click to fit the window")
    }
}
