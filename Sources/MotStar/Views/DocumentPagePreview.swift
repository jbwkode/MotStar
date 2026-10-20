import SwiftUI
import AppKit

/// Page preview for Office documents (DOCX/PPTX/XLSX).
///
/// Quick Look returns a page-proportioned image. A portrait page inside a
/// wide pane looks "narrow" if fitted by height, so we display it at
/// **fit-width** with vertical scrolling: the page fills the pane horizontally
/// and you scroll down the page. Double-click toggles fit-page ↔ fit-width.
struct DocumentPagePreview: View {
    let url: URL

    @State private var image: NSImage?
    @State private var failed: String?
    @State private var isLoading = true
    @State private var fitWidth = true

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    ScrollView(fitWidth ? .vertical : []) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(image.size, contentMode: .fit)
                            .frame(width: fitWidth ? max(240, geo.size.width - 28) : nil,
                                   height: fitWidth ? nil : max(240, geo.size.height - 28))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .onTapGesture(count: 2) { fitWidth.toggle() }
                            .help(fitWidth ? "Double-click for fit-page" : "Double-click for fit-width")
                    }
                } else if let failed {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.badge.exclamationmark")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        Text("Preview unavailable")
                            .font(.headline)
                        Text(failed)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        if isLoading {
                            Text("Rendering page…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .overlay(alignment: .bottomTrailing) {
                Text(fitWidth ? "Fit width · double-click to fit page" : "Fit page · double-click to fit width")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .task(id: url) {
            image = nil
            failed = nil
            isLoading = true
            do {
                let cgImage = try await PrintExportService.documentPageImage(for: url)
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } catch {
                failed = error.localizedDescription
            }
            isLoading = false
        }
    }
}
