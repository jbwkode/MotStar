import XCTest
@testable import MotStar

/// Pasted images must land in an `images/` folder beside the document being
/// edited — created on demand, reused when present, and named by timestamp so
/// two pastes never overwrite each other.
final class ImagePasteTests: XCTestCase {

    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotStarImagePasteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    private func makeDocument(in folder: String, name: String = "note.md") throws -> URL {
        let dir = sandbox.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try "# note\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    func testCreatesImagesFolderBesideDocument() throws {
        let doc = try makeDocument(in: "notes")
        let path = try ImagePasteStore.save(png, beside: doc)

        let imagesDir = doc.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        let written = doc.deletingLastPathComponent().appendingPathComponent(path)
        XCTAssertEqual(try Data(contentsOf: written), png)
    }

    func testUsesExistingImagesFolder() throws {
        let doc = try makeDocument(in: "notes")
        let imagesDir = doc.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try Data([0x00]).write(to: imagesDir.appendingPathComponent("existing.png"))

        let path = try ImagePasteStore.save(png, beside: doc)

        XCTAssertTrue(path.hasPrefix("images/"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: imagesDir.appendingPathComponent("existing.png").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: doc.deletingLastPathComponent().appendingPathComponent(path).path))
    }

    func testReturnedPathIsRelativeToDocumentFolder() throws {
        let doc = try makeDocument(in: "deep/nested")
        let path = try ImagePasteStore.save(png, beside: doc, now: Date(timeIntervalSince1970: 0))

        XCTAssertFalse(path.hasPrefix("/"))
        XCTAssertEqual(path, "images/image-\(ImagePasteStore.timestamp(Date(timeIntervalSince1970: 0))).png")
    }

    func testTimestampedNameInLocalTime() {
        // 2026-10-30 12:57:30 UTC; assert the shape, not a fixed offset — the
        // name is deliberately in the user's time zone.
        let name = ImagePasteStore.timestamp(Date(timeIntervalSince1970: 1_793_365_050))
        XCTAssertNotNil(name.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression))
    }

    func testSameSecondPastesDoNotOverwrite() throws {
        let doc = try makeDocument(in: "notes")
        let when = Date(timeIntervalSince1970: 1_793_365_050)

        let first = try ImagePasteStore.save(png, beside: doc, now: when)
        let second = try ImagePasteStore.save(Data([0x01]), beside: doc, now: when)

        XCTAssertNotEqual(first, second)
        let base = doc.deletingLastPathComponent()
        XCTAssertEqual(try Data(contentsOf: base.appendingPathComponent(first)), png)
        XCTAssertEqual(try Data(contentsOf: base.appendingPathComponent(second)), Data([0x01]))
    }

    func testEachDocumentGetsItsOwnImagesFolder() throws {
        let a = try makeDocument(in: "A", name: "a.md")
        let b = try makeDocument(in: "B", name: "b.md")

        let pathA = try ImagePasteStore.save(png, beside: a, now: Date(timeIntervalSince1970: 1))
        let pathB = try ImagePasteStore.save(png, beside: b, now: Date(timeIntervalSince1970: 2))

        let rootA = a.deletingLastPathComponent()
        let rootB = b.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootA.appendingPathComponent(pathA).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootB.appendingPathComponent(pathB).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootA.appendingPathComponent(pathB).path))
    }
}
