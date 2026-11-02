import XCTest
@testable import MotStar

/// YAML front matter must render as quiet metadata, never as a heading.
/// Regression for: fenced front matter becoming a bold `<h2>` because the
/// closing `---` made the block a setext heading.
final class FrontMatterTests: XCTestCase {

    private let fenced = """
    ---
    id: DESIGN-PROJ-01
    title: T Cell Care Project Overview and Releases
    version: "2.0"
    status: Draft
    owner: John B Walsh
    reviewers: []
    effective_date:
    ---

    # Real Heading

    Body text.
    """

    private let bare = """

    id: DESIGN-PROJ-01
    title: T Cell Care Project Overview
    version: "2.0"
    status: Draft
    owner: John B Walsh

    # Real Heading

    Body text.
    """

    func testFencedFrontMatterIsNotAHeading() {
        let html = MarkdownHTML.document(markdown: fenced)

        XCTAssertFalse(html.contains("<h2>"),
                       "front matter must not become a setext heading")
        XCTAssertFalse(html.contains("<hr />"),
                       "the opening fence must not survive as a horizontal rule")
        XCTAssertTrue(html.contains("<table class=\"frontmatter\">"))
        XCTAssertTrue(html.contains("<h1>Real Heading</h1>"))
        XCTAssertTrue(html.contains("Body text."))
    }

    func testFencedFrontMatterKeepsValuesAndDropsQuotes() {
        let html = MarkdownHTML.document(markdown: fenced)

        XCTAssertTrue(html.contains("<th>id</th><td>DESIGN-PROJ-01</td>"))
        XCTAssertTrue(html.contains("<th>version</th><td>2.0</td>"),
                      "surrounding quotes should not be rendered")
        XCTAssertTrue(html.contains("fm-empty"),
                      "an empty value renders as a placeholder, not 'key: '")
    }

    func testBareFrontMatterBlockIsRecognised() {
        let html = MarkdownHTML.document(markdown: bare)

        XCTAssertTrue(html.contains("<table class=\"frontmatter\">"))
        XCTAssertTrue(html.contains("<th>title</th>"))
        XCTAssertFalse(html.contains("id: DESIGN-PROJ-01"),
                       "the raw YAML lines must not leak into the body")
        XCTAssertTrue(html.contains("<h1>Real Heading</h1>"))
    }

    func testEnrichedRendererAlsoStripsFrontMatter() {
        let html = MarkdownHTML.document(markdown: fenced,
                                         baseDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(html.contains("<table class=\"frontmatter\">"))
        XCTAssertFalse(html.contains("<h2>"))
        XCTAssertTrue(html.contains("<h1>Real Heading</h1>"))
    }

    func testTwoLineProseIsNotMistakenForFrontMatter() {
        let prose = """
        Note: this explains the change
        Date: 30 October 2026

        Ordinary paragraphs follow.
        """
        let html = MarkdownHTML.document(markdown: prose)

        XCTAssertFalse(html.contains("<table class=\"frontmatter\">"),
                       "fewer than three key/value lines is ordinary text")
        XCTAssertTrue(html.contains("Note: this explains the change"))
    }

    func testFrontMatterMidDocumentIsLeftAlone() {
        let doc = """
        # Title

        key: value
        other: thing
        third: more

        Body.
        """
        let html = MarkdownHTML.document(markdown: doc)

        XCTAssertFalse(html.contains("<table class=\"frontmatter\">"),
                       "only front matter at the very top counts")
        XCTAssertTrue(html.contains("key: value"))
    }

    func testUnterminatedFenceIsTreatedAsContent() {
        let doc = """
        ---
        title: never closed

        # Heading
        """
        let html = MarkdownHTML.document(markdown: doc)

        XCTAssertFalse(html.contains("<table class=\"frontmatter\">"))
    }

    func testFrontMatterValuesAreEscaped() {
        let doc = """
        ---
        title: <script>alert(1)</script>
        ---

        Body.
        """
        let html = MarkdownHTML.document(markdown: doc)

        XCTAssertFalse(html.contains("<script>alert(1)</script>"),
                       "metadata values must be HTML-escaped")
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }
}
