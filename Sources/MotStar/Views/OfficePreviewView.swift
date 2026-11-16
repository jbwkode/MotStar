import SwiftUI
import PDFKit
import AppKit

/// Preview for Word documents.
///
/// `QLThumbnailGenerator` only ever returns the first page, so the whole
/// document is converted to a paginated PDF (the same conversion the PDF
/// export uses) and shown in a `PDFView` that fits the page to the pane width.
/// If conversion fails — or the file isn't a real OOXML document — the native
/// Quick Look view is used instead, which still scrolls every page.
struct OfficePreviewView: View {
    let url: URL

    @State private var document: PDFDocument?
    @State private var useQuickLook = false
    @State private var failedMessage: String?

    var body: some View {
        Group {
            if let document {
                FitWidthPDFRepresentable(document: document)
                    .ignoresSafeArea(.container, edges: .bottom)
            } else if useQuickLook {
                QuickLookView(url: url)
                    .ignoresSafeArea(.container, edges: .bottom)
            } else if let failedMessage {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Preview unavailable")
                        .font(.headline)
                    Text(failedMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Converting document…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .task(id: url) {
            document = nil
            useQuickLook = false
            failedMessage = nil
            do {
                let data = try await PrintExportService.pdfData(for: url)
                if let parsed = PDFDocument(data: data), parsed.pageCount > 0 {
                    document = parsed
                } else {
                    useQuickLook = true
                }
            } catch {
                NSLog("MotStar: DOCX preview conversion failed for %@ (%@) — using Quick Look",
                      url.lastPathComponent, error.localizedDescription)
                useQuickLook = true
            }
        }
    }
}

/// `PDFView` that keeps the page fitted to the pane's width (the pane is
/// usually wider than an A4 page, so aspect-fit would shrink the text).
/// User zoom is preserved until the pane is resized.
final class FitWidthPDFView: PDFView {
    private var lastLaidOutWidth: CGFloat = 0

    override func layout() {
        super.layout()
        if abs(bounds.width - lastLaidOutWidth) > 0.5 {
            lastLaidOutWidth = bounds.width
            fitPageToWidth()
        }
    }

    func fitPageToWidth() {
        guard let page = document?.page(at: 0) else { return }
        let pageWidth = page.bounds(for: .mediaBox).width
        guard pageWidth > 0, bounds.width > 60 else { return }
        let target = (bounds.width - 28) / pageWidth
        if abs(scaleFactor - target) > 0.002 {
            scaleFactor = target
        }
    }
}

/// Hosts a `FitWidthPDFView` for SwiftUI.
struct FitWidthPDFRepresentable: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> FitWidthPDFView {
        let view = FitWidthPDFView()
        view.document = document
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysAsBook = false
        view.autoScales = false
        view.backgroundColor = .underPageBackgroundColor
        view.pageShadowsEnabled = true
        return view
    }

    func updateNSView(_ view: FitWidthPDFView, context: Context) {
        if view.document !== document {
            view.document = document
            view.layoutSubtreeIfNeeded()
            view.fitPageToWidth()
        }
    }
}
