import XCTest
import PDFKit
@testable import MotStar

/// Regression coverage for PrintExportService — in particular that the markdown
/// → HTML → WebKit PDF path works in a packaged-style layout where the web
/// assets live in `Bundle.main` (Contents/Resources/web) and no SwiftPM
/// resource bundle is present. This used to crash in `Bundle.module` init.
final class PDFExportTests: XCTestCase {

    private func makeMarkdownFile(_ name: String = "note.md") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(name)
        let md = """
        # Export Title

        Some **bold** body text with a [link](https://example.com).

        ```swift
        let answer = 42
        ```
        """
        try md.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    func testMarkdownPDFExportProducesValidPDF() async throws {
        let url = try makeMarkdownFile()
        let data = try await PrintExportService.pdfData(for: url)

        XCTAssertFalse(data.isEmpty)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)),
                      "output should be a PDF (starts with %PDF)")

        guard let document = PDFDocument(data: data) else {
            return XCTFail("PDFDocument could not parse exported data")
        }
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        if let text = document.page(at: 0)?.string {
            XCTAssertTrue(text.contains("Export Title"))
            XCTAssertTrue(text.contains("bold body text"))
        }
    }

    @MainActor
    func testMarkdownPDFExportWithEnrichedFeatures() async throws {
        // Mermaid + KaTeX force the bundled web assets to load (the code path
        // that previously crashed in Bundle.module).
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("enriched.md")
        let md = """
        # Enriched

        Math: $$E = mc^2$$

        ```mermaid
        graph TD
            A --> B
        ```
        """
        try md.write(to: url, atomically: true, encoding: .utf8)

        let data = try await PrintExportService.pdfData(for: url)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertNotNil(PDFDocument(data: data))
    }

    @MainActor
    func testTextFilePDFExport() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("notes.txt")
        try "Plain text notes for export.".write(to: url, atomically: true, encoding: .utf8)

        let data = try await PrintExportService.pdfData(for: url)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertNotNil(PDFDocument(data: data))
    }
}

/// Word documents preview and export through the same full-document
/// conversion. Quick Look thumbnails only ever gave page 1, so this guards the
/// multi-page behaviour the preview relies on.
final class DocxPDFExportTests: XCTestCase {

    /// Builds a multi-page .docx via `textutil` (the same import path the app
    /// uses) so the fixture has real OOXML content.
    private func makeDocx(pages: Int = 4) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        var html = "<html><body>"
        for page in 1...pages {
            html += "<h1>Section \(page)</h1>"
            for line in 0..<32 {
                html += "<p>Section \(page) line \(line): the quick brown fox jumps over the lazy dog.</p>"
            }
            html += #"<p style="page-break-after:always"></p>"#
        }
        html += "</body></html>"

        let htmlURL = dir.appendingPathComponent("source.html")
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)
        let docxURL = dir.appendingPathComponent("report.docx")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "docx", htmlURL.path, "-output", docxURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "textutil could not build the fixture")
        return docxURL
    }

    @MainActor
    func testDocxExportContainsEveryPage() async throws {
        let url = try makeDocx(pages: 4)
        let data = try await PrintExportService.pdfData(for: url)

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(document.pageCount, 4,
                                    "the whole document must be rendered, not just page 1")

        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        for section in 1...4 {
            XCTAssertTrue(text.contains("Section \(section)"), "missing section \(section)")
        }
    }

    @MainActor
    func testDocxHTMLIsNonEmpty() throws {
        let url = try makeDocx(pages: 2)
        let html = try XCTUnwrap(PrintExportService.docxHTML(url: url))
        XCTAssertTrue(html.contains("Section 1"))
        XCTAssertTrue(html.contains("Section 2"))
    }
}

/// Printing must never blow the document up to fill the paper. A custom
/// NSView print with fit-pagination used to enlarge A4 content on larger
/// paper, which users saw as a huge print font.
final class PrintScalingTests: XCTestCase {

    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotStarPrintScaling-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    /// One A4 page with a 200 × 100 pt black block at (100, 100).
    private func makeSamplePDF() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(box)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 100, y: 100, width: 200, height: 100))
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    @MainActor
    private func printToFile(_ document: PDFDocument, paper: NSSize) throws -> Data {
        let info = NSPrintInfo()
        info.paperSize = paper
        info.jobDisposition = .save
        let url = sandbox.appendingPathComponent("print-\(UUID().uuidString).pdf")
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = try XCTUnwrap(PrintExportService.printOperation(for: document, printInfo: info))
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
        return try Data(contentsOf: url)
    }

    /// Bounding box (in points) of non-white pixels on page 1.
    private func inkBounds(_ data: Data) throws -> CGRect {
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        let box = page.bounds(for: .mediaBox)
        let w = Int(box.width), h = Int(box.height)
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.drawPDFPage(try XCTUnwrap(document.page(at: 0)?.pageRef))
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if buf[i] < 200 || buf[i + 1] < 200 || buf[i + 2] < 200 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    @MainActor
    func testPrintingOnLargerPaperDoesNotEnlargeContent() throws {
        let document = try XCTUnwrap(PDFDocument(data: makeSamplePDF()))
        let printed = try printToFile(document, paper: NSSize(width: 842, height: 1191)) // A3
        let ink = try inkBounds(printed)

        XCTAssertEqual(ink.width, 200, accuracy: 6,
                       "content must stay 1:1 (or shrink), never scale up to fill the paper")
        XCTAssertEqual(ink.height, 100, accuracy: 6)
    }

    @MainActor
    func testPrintingOnPaperSizeKeepsPages() throws {
        let document = try XCTUnwrap(PDFDocument(data: makeSamplePDF()))
        let printed = try printToFile(document, paper: NSSize(width: 595, height: 842))
        let output = try XCTUnwrap(PDFDocument(data: printed))
        XCTAssertEqual(output.pageCount, 1)
        let ink = try inkBounds(printed)
        XCTAssertEqual(ink.width, 200, accuracy: 6)
    }

    /// Printed markdown must use document body size. The print CSS previously
    /// reused the on-screen reading size (15 px, which WebKit maps 1:1 to
    /// points), so printed pages came out with very large text.
    @MainActor
    func testPrintedMarkdownUsesDocumentBodySize() async throws {
        let url = sandbox.appendingPathComponent("body-size.md")
        try """
        # Heading

        Body text used to measure the printed font size on the page.

        - one
        - two
        """.write(to: url, atomically: true, encoding: .utf8)

        let data = try await PrintExportService.pdfData(for: url)
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        let attributed = page.attributedString ?? NSAttributedString()

        var sizes: [CGFloat] = []
        attributed.enumerateAttribute(.font,
                                      in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let font = value as? NSFont, range.length > 0 {
                sizes.append(font.pointSize)
            }
        }
        let body = try XCTUnwrap(sizes.filter { $0 < 14 }.max(),
                                 "no body text found on the printed page")
        XCTAssertLessThanOrEqual(body, 12.5,
                                 "body text must print at document size (~11 pt), not the 15 px screen size")
        XCTAssertGreaterThanOrEqual(body, 9)
    }
}

/// Page numbers are stamped onto the print copy only, so prints can be
/// collated. Exported PDFs are unaffected.
final class PageNumberTests: XCTestCase {

    private func makePDF(pages: Int) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(box)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 100, y: 600, width: 200, height: 40))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    /// Bottom-most dark pixel row (bitmap row 0 is the top of the page, so the
    /// footer near the bottom margin is a high row index).
    private func bottomInkRow(_ page: CGPDFPage) -> Int {
        let box = page.getBoxRect(.mediaBox)
        let w = Int(box.width), h = Int(box.height)
        var buffer = [UInt8](repeating: 255, count: w * h * 4)
        let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.drawPDFPage(page)
        var last = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if buffer[i] < 200 || buffer[i + 1] < 200 || buffer[i + 2] < 200 {
                    last = y
                }
            }
        }
        return last
    }

    func testMultiPagePrintGetsFooterOnEveryPage() {
        let source = makePDF(pages: 3)
        let stamped = PDFPageNumbers.stamping(source, fileName: "design_app_ux.md")

        let doc = CGPDFDocument(CGDataProvider(data: stamped as CFData)!)!
        XCTAssertEqual(doc.numberOfPages, 3)
        for index in 1...3 {
            let page = doc.page(at: index)!
            // The body block sits near the top of the page; the footer adds
            // ink close to the bottom edge.
            XCTAssertGreaterThan(bottomInkRow(page), 800,
                                 "page \(index) should carry a footer near the bottom margin")
        }
    }

    func testSinglePageIsLeftAlone() {
        let source = makePDF(pages: 1)
        let stamped = PDFPageNumbers.stamping(source)
        XCTAssertEqual(stamped, source)
    }

    func testPageSizeIsPreserved() {
        let stamped = PDFPageNumbers.stamping(makePDF(pages: 2))
        let doc = CGPDFDocument(CGDataProvider(data: stamped as CFData)!)!
        let box = doc.page(at: 1)!.getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 595, accuracy: 0.5)
        XCTAssertEqual(box.height, 842, accuracy: 0.5)
    }
}

/// The print footer carries the document name on the left and the page number
/// on the right, both within the text margins.
final class FooterContentTests: XCTestCase {

    private func makePDF(pages: Int) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(box)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 100, y: 600, width: 200, height: 40))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    /// Rows from the bottom that contain ink, plus the min/max column of the
    /// footer band.
    private func footerInk(_ page: CGPDFPage) -> (minX: Int, maxX: Int, rows: Int) {
        let box = page.getBoxRect(.mediaBox)
        let w = Int(box.width), h = Int(box.height)
        var buffer = [UInt8](repeating: 255, count: w * h * 4)
        let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.drawPDFPage(page)
        var minX = w, maxX = 0, rows = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if buffer[i] < 200 || buffer[i + 1] < 200 || buffer[i + 2] < 200 {
                    minX = min(minX, x); maxX = max(maxX, x); rows += 1
                }
            }
        }
        return (minX, maxX, rows)
    }

    func testFooterHasNameLeftAndPageNumberRight() throws {
        let stamped = PDFPageNumbers.stamping(makePDF(pages: 2), fileName: "design_app_ux.md")
        let provider = try XCTUnwrap(CGDataProvider(data: stamped as CFData))
        let doc = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(doc.page(at: 1))

        // Ink must reach both the left margin area (file name) and the right
        // margin area (page number), and stay inside the 51 pt margins.
        let ink = footerInk(page)
        XCTAssertLessThan(ink.minX, 80, "file name should start at the left margin")
        XCTAssertGreaterThan(ink.maxX, 500, "page number should end at the right margin")
        XCTAssertGreaterThan(ink.rows, 20, "footer text should be present")
    }

    func testLongFileNameIsTruncatedWithinMargins() throws {
        let longName = String(repeating: "very-long-document-name-", count: 8) + ".md"
        let stamped = PDFPageNumbers.stamping(makePDF(pages: 2), fileName: longName)
        let provider = try XCTUnwrap(CGDataProvider(data: stamped as CFData))
        let doc = try XCTUnwrap(CGPDFDocument(provider))
        let ink = footerInk(try XCTUnwrap(doc.page(at: 1)))
        XCTAssertGreaterThanOrEqual(ink.minX, 45, "footer must not run off the left margin")
        XCTAssertLessThanOrEqual(ink.maxX, 550, "footer must not run off the right margin")
    }
}
