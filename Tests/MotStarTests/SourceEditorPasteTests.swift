import XCTest
import SwiftUI
import AppKit
@testable import MotStar

/// End-to-end checks on the live editor view: the text view must size itself
/// inside the scroll view, and ⌘V of a clipboard image must write the PNG into
/// `<document folder>/images/` and insert a relative Markdown link.
@MainActor
final class SourceEditorPasteTests: XCTestCase {

    private var sandbox: URL!
    private var savedClipboardString: String?

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotStarEditorPasteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        savedClipboardString = NSPasteboard.general.string(forType: .string)
    }

    override func tearDownWithError() throws {
        if let savedClipboardString {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(savedClipboardString, forType: .string)
        }
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    private func makeHostedEditor() throws -> (NSHostingView<SourceEditorView>, SourceEditorView, URL, MarkdownEditorTextView) {
        let url = sandbox.appendingPathComponent("note.md")
        try "# note\n\n".write(to: url, atomically: true, encoding: .utf8)

        let document = TextDocument(url: url)
        document.load()

        let view = SourceEditorView(document: document, wrap: true, fontSize: 13)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()

        guard let textView = Self.findTextView(in: host) as? MarkdownEditorTextView else {
            XCTFail("SourceEditorView did not create a MarkdownEditorTextView")
            throw XCTSkip("no text view")
        }
        return (host, view, url, textView)
    }

    private static func findTextView(in view: NSView) -> NSView? {
        if view is NSTextView { return view }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }

    func testEditorTextFillsAvailableWidth() throws {
        let (_, _, _, textView) = try makeHostedEditor()

        XCTAssertGreaterThan(textView.frame.width, 0, "editor must receive its width from the scroll view")
        XCTAssertEqual((textView.string as NSString).trimmingCharacters(in: .whitespacesAndNewlines),
                       "# note")
        XCTAssertTrue(textView.isEditable)
    }

    func testPastingImageWritesFileAndInsertsRelativeLink() throws {
        let (_, _, url, textView) = try makeHostedEditor()

        let png = try makeTinyPNG()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)

        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.paste(nil)

        let imagesDir = sandbox.appendingPathComponent("images", isDirectory: true)
        let written = try FileManager.default
            .contentsOfDirectory(atPath: imagesDir.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(written.count, 1)

        let inserted = textView.string
        XCTAssertTrue(inserted.hasSuffix("![](images/\(written[0]))"),
                      "editor should insert a path relative to the document: \(inserted)")

        // The file on disk is the pasted bitmap, so the link resolves.
        let data = try Data(contentsOf: imagesDir.appendingPathComponent(written[0]))
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(url.deletingLastPathComponent().path, sandbox.path)
    }

    func testPasteStaysEnabledForImageOnlyClipboard() throws {
        let (_, _, _, textView) = try makeHostedEditor()
        let item = NSMenuItem(title: "Paste", action: #selector(NSTextView.paste(_:)), keyEquivalent: "v")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("hello", forType: .string)
        XCTAssertTrue(textView.validateUserInterfaceItem(item))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(try makeTinyPNG(), forType: .png)
        XCTAssertTrue(textView.validateUserInterfaceItem(item),
                      "an image-only clipboard must keep Edit ▸ Paste enabled")

        NSPasteboard.general.clearContents()
        XCTAssertFalse(textView.validateUserInterfaceItem(item))
    }

    func testPastingTextIsUntouched() throws {
        let (_, _, _, textView) = try makeHostedEditor()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("hello", forType: .string)

        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.paste(nil)

        XCTAssertTrue(textView.string.hasSuffix("hello"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sandbox.appendingPathComponent("images").path))
    }

    /// 2×2 opaque PNG produced by AppKit, so the test doesn't ship a fixture.
    private func makeTinyPNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
