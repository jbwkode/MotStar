import XCTest
@testable import MotStar

/// Coverage for discarding unsaved edits via `TextDocument.revert()`.
@MainActor
final class TextDocumentTests: XCTestCase {

    private func makeFile(_ contents: String, name: String = "note.md") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testRevertDiscardsUnsavedEdits() throws {
        let url = try makeFile("# Saved\n")
        let doc = TextDocument(url: url)
        doc.load()
        XCTAssertFalse(doc.isDirty)
        let revisionAfterLoad = doc.revision

        doc.text = "# Edited\n"
        XCTAssertTrue(doc.isDirty)

        doc.revert()

        XCTAssertEqual(doc.text, "# Saved\n")
        XCTAssertFalse(doc.isDirty)
        XCTAssertGreaterThan(doc.revision, revisionAfterLoad,
                             "revert should signal a fresh read from disk")
    }

    func testRevertPicksUpExternalDiskChanges() throws {
        let url = try makeFile("original")
        let doc = TextDocument(url: url)
        doc.load()
        doc.text = "draft"
        try "changed on disk".write(to: url, atomically: true, encoding: .utf8)

        doc.revert()

        XCTAssertEqual(doc.text, "changed on disk")
        XCTAssertFalse(doc.isDirty)
    }

    func testSaveClearsDirtyStateWithoutBumpingRevision() throws {
        let url = try makeFile("start")
        let doc = TextDocument(url: url)
        doc.load()
        let revisionAfterLoad = doc.revision

        doc.text = "saved text"
        try doc.save()

        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "saved text")
        XCTAssertEqual(doc.revision, revisionAfterLoad,
                       "saving should not look like a reload")
    }

    func testRevertKeepsDraftWhenFileUnreadable() throws {
        let url = try makeFile("keep me")
        let doc = TextDocument(url: url)
        doc.load()
        doc.text = "draft"
        try FileManager.default.removeItem(at: url)

        doc.revert()

        XCTAssertTrue(doc.isDirty, "an unreadable file must not silently drop the draft")
        XCTAssertEqual(doc.text, "draft")
    }
}
