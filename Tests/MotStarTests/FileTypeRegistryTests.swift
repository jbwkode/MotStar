import XCTest
@testable import MotStar

final class FileTypeRegistryTests: XCTestCase {

    func file(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/fixture/\(name)")
    }

    func testClassifiesEachRegisteredType() {
        XCTAssertEqual(FileTypeRegistry.kind(for: file("a.md"), isFolder: false), .markdown)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("a.markdown"), isFolder: false), .markdown)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("notes.txt"), isFolder: false), .text)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("brief.pdf"), isFolder: false), .pdf)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("doc.docx"), isFolder: false), .docx)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("deck.pptx"), isFolder: false), .pptx)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("book.xlsx"), isFolder: false), .xlsx)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("photo.jpg"), isFolder: false), .image)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("photo.jpeg"), isFolder: false), .image)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("pic.PNG"), isFolder: false), .image)
    }

    func testClassificationIsCaseInsensitive() {
        XCTAssertEqual(FileTypeRegistry.kind(for: file("BRIEF.MD"), isFolder: false), .markdown)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("Report.DOCX"), isFolder: false), .docx)
    }

    func testUnknownTypeIsOther() {
        XCTAssertEqual(FileTypeRegistry.kind(for: file("archive.zip"), isFolder: false), .other)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("clip.mov"), isFolder: false), .other)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("noextension"), isFolder: false), .other)
    }

    func testClassifiesSourceCodeFiles() {
        let codeFiles = ["main.swift", "util.py", "app.js", "x.ts", "y.tsx", "lib.c",
                         "main.cpp", "a.h", "b.cs", "go.mod.go", "main.rs", "script.sh",
                         "style.css", "page.html", "query.sql", "Main.kt", "file.rb"]
        for name in codeFiles {
            XCTAssertEqual(FileTypeRegistry.kind(for: file(name), isFolder: false), .code,
                           "expected .code for \(name)")
        }
        // Plain text and markdown stay distinct from code.
        XCTAssertEqual(FileTypeRegistry.kind(for: file("notes.txt"), isFolder: false), .text)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("note.md"), isFolder: false), .markdown)
    }

    func testFolderIsFolderRegardlessOfName() {
        XCTAssertEqual(FileTypeRegistry.kind(for: file("Reports"), isFolder: true), .folder)
        XCTAssertEqual(FileTypeRegistry.kind(for: file("notes.txt"), isFolder: true), .folder)
    }

    func testMarkersAndSymbolsDefinedForEveryKind() {
        for kind in FileKind.allCases {
            XCTAssertFalse(kind.symbolName.isEmpty)
            if kind == .folder {
                XCTAssertNil(kind.markerRGB, "folders have no colour marker")
            } else {
                let rgb = kind.markerRGB
                XCTAssertNotNil(rgb)
                let (r, g, b) = rgb!
                XCTAssertTrue(r >= 0 && r <= 1 && g >= 0 && g <= 1 && b >= 0 && b <= 1)
            }
        }
    }
}
