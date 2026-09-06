import XCTest
@testable import MotStar

final class MarkdownOutlineTests: XCTestCase {

    func testParsesATXHeadingsWithLevels() {
        let md = "# One\n\n## Two\n\n### Three\n\nText\n\n#### Four"
        let outline = MarkdownOutline.parse(md)
        XCTAssertEqual(outline.map(\.level), [1, 2, 3, 4])
        XCTAssertEqual(outline.map(\.text), ["One", "Two", "Three", "Four"])
        XCTAssertEqual(outline.map(\.line), [1, 3, 5, 9])
    }

    func testRequiresSpaceAfterHashes() {
        let md = "#Heading\n\n##Heading2\n\n# Real"
        let outline = MarkdownOutline.parse(md)
        XCTAssertEqual(outline.map(\.text), ["Real"])
        XCTAssertEqual(outline.count, 1)
    }

    func testIgnoresCodeFences() {
        let md = "# Visible\n\n```\n# hidden one\n## hidden two\n```\n\n# Also visible"
        let outline = MarkdownOutline.parse(md)
        XCTAssertEqual(outline.map(\.text), ["Visible", "Also visible"])
    }

    func testStripsClosingHashesAndInlineMarkers() {
        let md = "## Heading ##\n\n# **Bold** and `code`"
        let outline = MarkdownOutline.parse(md)
        XCTAssertEqual(outline.map(\.text), ["Heading", "Bold and code"])
    }

    func testParsesSetextHeadings() {
        let md = "Document Title\n===\n\nSome intro.\n\nSection Two\n---"
        let outline = MarkdownOutline.parse(md)
        XCTAssertEqual(outline.map(\.text), ["Document Title", "Section Two"])
        XCTAssertEqual(outline.map(\.level), [1, 2])
        XCTAssertEqual(outline.map(\.line), [1, 6])
    }

    func testIgnoresThematicBreakAfterBlankLine() {
        // A lone "---" not preceded by a text line is a rule, not a heading.
        let md = "Intro\n\n---\n\n# Real"
        let outline = MarkdownOutline.parse(md)
        XCTAssertEqual(outline.map(\.text), ["Real"])
    }

    func testDeepLevelsBeyondSixIgnored() {
        let md = "####### Too deep\n\n# Fine"
        let outline = MarkdownOutline.parse(md)
        XCTAssertEqual(outline.map(\.text), ["Fine"])
    }

    func testEmptyAndHeadingOnlyDocuments() {
        XCTAssertTrue(MarkdownOutline.parse("").isEmpty)
        let outline = MarkdownOutline.parse("# Only\n\nText without headings")
        XCTAssertEqual(outline.count, 1)
    }
}
