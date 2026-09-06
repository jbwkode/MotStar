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
