import SwiftUI
import AppKit

/// Page preview for Office documents (DOCX/PPTX/XLSX). Quick Look's preview
/// view renders such pages on a padded square canvas and shows them at their
/// narrow native width, so we render a trimmed, high-resolution page image
/// and scale it to fit the pane instead.
struct DocumentPagePreview: View {
    let url: URL

    @State private var image: NSImage?
    @State private var failed: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                GeometryReader { _ in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .underPageBackgroundColor))
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("First-page preview")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(6)
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
                    Text(isLoading ? "Rendering page…" : "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
