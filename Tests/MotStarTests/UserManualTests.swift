import XCTest
@testable import MotStar

/// Help → MotStar User Manual: the manual opens in the preview pane and is
/// treated as read-only, and opening it must not disturb the new-file location.
@MainActor
final class UserManualTests: XCTestCase {

    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotStarManualTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: AppState.lastDirectoryKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: AppState.lastDirectoryKey)
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    func testOpeningManualShowsItInPreview() throws {
        let app = AppState()

        app.openUserManual()

        let selected = try XCTUnwrap(app.selectedURL)
        XCTAssertEqual(selected.lastPathComponent, "USER-MANUAL.md")
        XCTAssertEqual(app.paneMode, .preview)
        XCTAssertEqual(app.markdownDisplayMode, .formatted)
    }

    /// The bundled manual is read-only (you cannot write into the app bundle).
    /// Unbundled runs use the repo copy, which is editable — skip there.
    func testBundledManualIsReadOnly() throws {
        let app = AppState()
        app.openUserManual()

        let url = try XCTUnwrap(app.selectedURL)
        guard let resources = Bundle.main.resourceURL?.standardizedFileURL.path,
              url.standardizedFileURL.path.hasPrefix(resources + "/") else {
            throw XCTSkip("unbundled run: the manual is the editable repo copy")
        }
        XCTAssertFalse(app.isSelectionEditable, "the bundled manual must be read-only")
    }

    func testOpeningManualDoesNotChangeNewFileLocation() throws {
        let folder = sandbox.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let note = folder.appendingPathComponent("note.md")
        try "# note\n".write(to: note, atomically: true, encoding: .utf8)

        let app = AppState()
        app.selectFile(note)
        XCTAssertEqual(app.preferredNewFileDirectory?.resolvingSymlinksInPath().path,
                       folder.resolvingSymlinksInPath().path)

        app.openUserManual()

        XCTAssertEqual(app.preferredNewFileDirectory?.resolvingSymlinksInPath().path,
                       folder.resolvingSymlinksInPath().path,
                       "help should not move the new-file panel into the app bundle")
    }

    func testFilesInsideTheBundleAreReadOnly() throws {
        guard let resources = Bundle.main.resourceURL else {
            throw XCTSkip("test bundle has no resources directory")
        }
        let app = AppState()
        app.selectFile(resources.appendingPathComponent("UserManual.md"))

        XCTAssertFalse(app.isSelectionEditable)
    }
}
