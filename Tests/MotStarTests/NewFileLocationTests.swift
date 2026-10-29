import XCTest
@testable import MotStar

/// New files should default to the folder the user was last working in.
@MainActor
final class NewFileLocationTests: XCTestCase {

    private var sandbox: URL!
    /// Same defaults domain AppState's PersistenceService writes roots to.
    private let rootsKey = "navstar.rootFolders.v1"

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotStarNewFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        // Start from a clean slate: no remembered folder, no roots.
        UserDefaults.standard.removeObject(forKey: AppState.lastDirectoryKey)
        UserDefaults.standard.removeObject(forKey: rootsKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: AppState.lastDirectoryKey)
        UserDefaults.standard.removeObject(forKey: rootsKey)
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    /// Creates `<sandbox>/<name>/` plus a file inside it, returning both URLs.
    private func makeFolder(_ name: String, file: String = "note.md") throws -> (URL, URL) {
        let folder = sandbox.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent(file)
        try "# note\n".write(to: fileURL, atomically: true, encoding: .utf8)
        return (folder, fileURL)
    }

    private func path(_ url: URL?) -> String? {
        url?.resolvingSymlinksInPath().path
    }

    func testDefaultsToFolderOfSelectedFile() throws {
        let (folderA, fileA) = try makeFolder("A")
        let app = AppState()

        app.selectFile(fileA)

        XCTAssertEqual(path(app.preferredNewFileDirectory), path(folderA))
    }

    func testLandsInFolderOfMostRecentlySelectedFile() throws {
        let (folderA, fileA) = try makeFolder("A")
        let (folderB, fileB) = try makeFolder("B")
        let app = AppState()

        app.selectFile(fileA)
        app.selectFile(fileB)

        XCTAssertEqual(path(app.preferredNewFileDirectory), path(folderB))
        XCTAssertNotEqual(path(app.preferredNewFileDirectory), path(folderA))
    }

    func testExpandingFolderCountsAsNavigation() throws {
        let (_, fileA) = try makeFolder("A")
        let (folderB, _) = try makeFolder("B")
        let app = AppState()

        app.selectFile(fileA)
        app.setExpanded(folderB.path, true)

        XCTAssertEqual(path(app.preferredNewFileDirectory), path(folderB))
    }

    func testRememberedFolderSurvivesRelaunch() throws {
        let (folderB, fileB) = try makeFolder("B")

        do {
            let app = AppState()
            app.selectFile(fileB)
        }

        // A fresh instance reads the persisted path, as on next launch.
        let relaunched = AppState()

        XCTAssertEqual(path(relaunched.preferredNewFileDirectory), path(folderB))
    }

    func testFallsBackToFirstRootFolderBeforeAnyNavigation() throws {
        let (folderA, _) = try makeFolder("A")
        PersistenceService().save([RootFolder(path: folderA.path)])

        let app = AppState()
        XCTAssertNil(UserDefaults.standard.string(forKey: AppState.lastDirectoryKey))
        XCTAssertEqual(path(app.preferredNewFileDirectory), path(folderA))
    }

    func testIgnoresRememberedFolderThatNoLongerExists() throws {
        let (folderA, fileA) = try makeFolder("A")
        let (folderB, _) = try makeFolder("B")
        let app = AppState()

        app.selectFile(fileA)
        app.setExpanded(folderB.path, true)   // remembers B
        try FileManager.default.removeItem(at: folderB)

        // Stale path is skipped; the live selection wins.
        XCTAssertEqual(path(app.preferredNewFileDirectory), path(folderA))
    }
}
