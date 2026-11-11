import XCTest
@testable import MotStar

final class OneDriveShareTests: XCTestCase {

    func testLocatesOneDriveCloudStorageFile() {
        let url = URL(fileURLWithPath: "/Users/x/Library/CloudStorage/OneDrive-Personal(2)/OD-OW/notes.md")
        let loc = OneDriveShareService.locate(url)
        XCTAssertEqual(loc?.displayName, "OneDrive-Personal(2)")
        XCTAssertEqual(loc?.relativePath, "OD-OW/notes.md")
        XCTAssertEqual(loc?.root.path, "/Users/x/Library/CloudStorage/OneDrive-Personal(2)")
    }

    func testLocatesSharePointCloudStorageFile() {
        let url = URL(fileURLWithPath: "/Users/x/Library/CloudStorage/SharePoint-Contoso/Finance/q3.md")
        let loc = OneDriveShareService.locate(url)
        XCTAssertEqual(loc?.displayName, "SharePoint-Contoso")
        XCTAssertEqual(loc?.relativePath, "Finance/q3.md")
    }

    func testIgnoresOtherCloudStorageProviders() {
        let url = URL(fileURLWithPath: "/Users/x/Library/CloudStorage/iCloud Drive/notes.md")
        XCTAssertNil(OneDriveShareService.locate(url))
    }

    func testIgnoresOrdinaryLocalFiles() {
        XCTAssertNil(OneDriveShareService.locate(URL(fileURLWithPath: "/Users/x/Documents/notes.md")))
    }

    func testLocatesLegacyHomeOneDriveFile() {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/OneDrive/notes.md")
        let loc = OneDriveShareService.locate(url)
        XCTAssertEqual(loc?.displayName, "OneDrive")
        XCTAssertEqual(loc?.relativePath, "notes.md")
    }
}
