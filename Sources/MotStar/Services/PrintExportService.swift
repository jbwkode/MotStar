import AppKit
import WebKit
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import ImageIO

enum PrintExportError: LocalizedError {
    case cannotReadFile
    case cannotLoadDocument
    case renderingFailed(String)
    case thumbnailUnavailable
    case previewUnavailable(String)
    case timedOut
    case noImageContent

    var errorDescription: String? {
        switch self {
        case .cannotReadFile: return "The file could not be read."
        case .cannotLoadDocument: return "The document could not be prepared."
        case .renderingFailed(let detail): return "Rendering failed: \(detail)"
        case .thumbnailUnavailable: return "No preview image could be generated for this file type."
        case .previewUnavailable(let detail): return detail
        case .timedOut: return "The document took too long to render."
        case .noImageContent: return "The image could not be decoded."
        }
    }
}

/// Print and Export-as-PDF for the selected file.
///
/// Per-kind strategy (kind detection via `FileTypeRegistry`):
///  - `.markdown` / `.text`: rendered HTML → paginated PDF (WKWebView)
///  - `.pdf`: passthrough of the original bytes
///  - `.image`: full-resolution single-page PDF
///  - office types & everything else: Quick Look thumbnail page (best effort)
enum PrintExportService {

    // MARK: Public API (main actor — touches UI-adjacent frameworks)

    /// Produces PDF data for the given file. `draftText` (an unsaved editor
    /// buffer for markdown/text files) is rendered when provided;
    /// `wikilinkRoots` resolve `[[…]]` references in Markdown.
    @MainActor
    static func pdfData(for url: URL, draftText: String? = nil, wikilinkRoots: [URL] = []) async throws -> Data {
        let kind = FileTypeRegistry.kind(for: url)
        switch kind {
        case .folder:
            throw PrintExportError.cannotReadFile
        case .markdown:
            let html: String?
            if let draftText {
                html = MarkdownHTML.document(markdown: draftText,
                                             baseDirectory: url.deletingLastPathComponent(),
                                             wikilinkRoots: wikilinkRoots)
            } else if let text = MarkdownHTML.readText(url) {
                html = MarkdownHTML.document(markdown: text,
                                             baseDirectory: url.deletingLastPathComponent(),
                                             wikilinkRoots: wikilinkRoots)
            } else {
                html = nil
            }
            guard let html else { throw PrintExportError.cannotReadFile }
            return try await renderPaginatedPDF(html: html)
        case .text:
            guard let text = draftText ?? Self.loadText(url) else {
                throw PrintExportError.cannotReadFile
            }
            return try await renderPaginatedPDF(html: TextHTML.document(text: text))
        case .code:
            guard let text = draftText ?? Self.loadText(url) else {
                throw PrintExportError.cannotReadFile
            }
            return try await renderPaginatedPDF(html: CodeHTML.document(text: text, fontSize: 10))
        case .pdf:
            return try Data(contentsOf: url)
        case .image:
            return try Self.imagePDF(url: url)
        case .docx, .pptx, .xlsx, .other:
            return try await Self.quickLookPDF(url: url)
        }
    }

    /// Prints the selected file through the standard macOS print dialog.
    ///
    /// Pages are drawn directly from the PDF document (see
    /// `PDFPagesPrintView`) instead of printing an off-screen PDFView, which
    /// can produce blank pages when the view has no laid-out frame.
    @MainActor
    static func print(_ url: URL, draftText: String? = nil, wikilinkRoots: [URL] = []) async throws {
        let data = try await pdfData(for: url, draftText: draftText, wikilinkRoots: wikilinkRoots)
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw PrintExportError.cannotLoadDocument
        }
        let printView = PDFPagesPrintView(document: document)

        let operation = NSPrintOperation(view: printView)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        // Match the PDF page exactly — no default letter margins or cropping.
        operation.printInfo.topMargin = 0
        operation.printInfo.bottomMargin = 0
        operation.printInfo.leftMargin = 0
        operation.printInfo.rightMargin = 0
        operation.printInfo.horizontalPagination = .fit
        operation.printInfo.verticalPagination = .fit
        operation.run()
    }

    /// Prints a PDF document by drawing every page directly — one print page
    /// per PDF page, laid out at the page's media-box size (1:1, no scaling or
    /// cropping by an un-laid-out view).
    private final class PDFPagesPrintView: NSView {
        private let document: PDFDocument
        private var pageRects: [NSRect] = []

        init(document: PDFDocument) {
            self.document = document
            super.init(frame: .zero)

            var x: CGFloat = 0
            var y: CGFloat = 0
            var width: CGFloat = 0
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                pageRects.append(NSRect(x: x, y: y, width: bounds.width, height: bounds.height))
                y += bounds.height
                width = max(width, bounds.width)
            }
            frame = NSRect(x: 0, y: 0, width: width, height: max(y, 1))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func knowsPageRange(_ range: NSRangePointer) -> Bool {
            guard !pageRects.isEmpty else { return false }
            range.pointee = NSRange(location: 1, length: pageRects.count)
            return true
        }

        override func rectForPage(_ page: Int) -> NSRect {
            guard pageRects.indices.contains(page - 1) else { return NSRect.zero }
            return pageRects[page - 1]
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            for (index, rect) in pageRects.enumerated() {
                guard rect.intersects(dirtyRect), let page = document.page(at: index) else { continue }
                context.saveGState()
                context.translateBy(x: rect.minX, y: rect.minY)
                page.draw(with: .mediaBox, to: context)
                context.restoreGState()
            }
        }
    }

    // MARK: HTML → paginated PDF

    /// Renders HTML in an off-screen WKWebView and captures a paginated PDF.
    /// The default `WKPDFConfiguration` (rect zero) captures the entire
    /// document; `@page` CSS controls paper size and margins. JavaScript is
    /// enabled so bundled Mermaid diagrams render; we settle briefly after
    /// page load for async diagram/image work before capturing.
    @MainActor
    private static func renderPaginatedPDF(html: String) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842),
                                configuration: configuration)
        let waiter = WebLoadWaiter(webView: webView)
        webView.loadHTMLString(html, baseURL: nil)

        do {
            try await waiter.waitUntilLoaded(timeoutNanoseconds: 20_000_000_000)
        } catch {
            throw PrintExportError.renderingFailed(error.localizedDescription)
        }
        // Let Mermaid (and any image decode) finish before capturing.
        try await Task.sleep(nanoseconds: 1_600_000_000)

        let pdfConfiguration = WKPDFConfiguration()
        return try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: pdfConfiguration) { result in
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Observes load completion for the off-screen web view.
    private final class WebLoadWaiter: NSObject, WKNavigationDelegate {
        private weak var webView: WKWebView?
        private var continuation: CheckedContinuation<Void, Error>?
        private var didFinish = false

        init(webView: WKWebView) {
            self.webView = webView
            super.init()
            webView.navigationDelegate = self
        }

        func waitUntilLoaded(timeoutNanoseconds: UInt64) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                if self.didFinish {
                    self.finish()
                    return
                }
                Task {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    if !self.didFinish {
                        self.finish(throwing: PrintExportError.timedOut)
                    }
                }
            }
        }

        private func finish(throwing error: Error? = nil) {
            guard !didFinish else { return }
            didFinish = true
            webView?.navigationDelegate = nil
            continuation?.resume(with: error.map(Result.failure) ?? .success(()))
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(throwing: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(throwing: error)
        }
    }

    // MARK: Text helpers

    private static func loadText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: Image → PDF

    /// Wraps the source image in a single-page PDF at native resolution.
    private static func imagePDF(url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PrintExportError.noImageContent
        }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw PrintExportError.cannotLoadDocument
        }

        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PrintExportError.cannotLoadDocument
        }
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    // MARK: Quick Look snapshot → PDF (office & other types)

    /// Generates a Quick Look thumbnail and places it on an A4 page.
    /// Tries a full-size thumbnail first, then a lighter request, then the
    /// file icon; surfaces a friendly error if Quick Look has nothing.
    @MainActor
    private static func quickLookPDF(url: URL) async throws -> Data {
        let image = try await documentPageImage(for: url)

        let pageSize = CGSize(width: 595, height: 842) // A4 @ 72 dpi
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw PrintExportError.cannotLoadDocument
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PrintExportError.cannotLoadDocument
        }
        context.beginPDFPage(nil)

        // White page background, then the (trimmed) page image fit inside
        // with modest margins — avoids the narrow "postage stamp" result.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(mediaBox)

        let scale = min((pageSize.width - 48) / CGFloat(image.width),
                        (pageSize.height - 48) / CGFloat(image.height))
        let drawSize = CGSize(width: CGFloat(image.width) * scale,
                              height: CGFloat(image.height) * scale)
        let origin = CGPoint(x: (pageSize.width - drawSize.width) / 2,
                             y: (pageSize.height - drawSize.height) / 2)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: origin, size: drawSize))

        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    /// Best Quick Look page image for a document, with the padded canvas
    /// whitespace trimmed off (Office docs render on a padded square canvas,
    /// which otherwise makes the page look narrow).
    @MainActor
    static func documentPageImage(for url: URL) async throws -> CGImage {
        let raw = try await bestQuickLookImage(for: url)
        return ImageTrimming.trimmedWhitespace(raw)
    }

    /// Returns the best CGImage Quick Look can produce for a file: full-size
    /// thumbnail → lighter thumbnail → file icon. Throws a friendly error
    /// when Quick Look has nothing for the file.
    @MainActor
    private static func bestQuickLookImage(for url: URL) async throws -> CGImage {
        let attempts: [(NSSize, CGFloat, QLThumbnailGenerator.Request.RepresentationTypes)] = [
            (NSSize(width: 2048, height: 2048), 2, [.thumbnail]),
            (NSSize(width: 1024, height: 1024), 1, [.thumbnail]),
            (NSSize(width: 256, height: 256), 1, [.icon])
        ]

        for (size, scale, types) in attempts {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: types)
            do {
                let representation = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QLThumbnailRepresentation, Error>) in
                    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
                        if let rep {
                            continuation.resume(returning: rep)
                        } else {
                            continuation.resume(throwing: error ?? PrintExportError.thumbnailUnavailable)
                        }
                    }
                }
                let image = representation.nsImage
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    return cgImage
                }
            } catch {
                // Try the next, lighter representation.
                continue
            }
        }

        throw PrintExportError.previewUnavailable(
            "Quick Look couldn't produce a preview for this file type. Export/print it from its own app (e.g. Word) instead."
        )
    }
}

/// Minimal HTML wrapper for plain text so it can share the WebKit PDF path.
enum TextHTML {
    static func document(text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let css = """
        body { margin: 0; padding: 24px 30px; font-family: ui-monospace, Menlo, monospace; font-size: 10pt; line-height: 1.5; color: #111; background: #fff; }
        pre { white-space: pre-wrap; word-wrap: break-word; }
        @media print { body { padding: 0; } }
        @page { size: A4; margin: 12mm; }
        """
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>\(css)</style></head>
        <body><pre>\(escaped)</pre></body></html>
        """
    }
}
