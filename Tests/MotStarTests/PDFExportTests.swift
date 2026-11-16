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
