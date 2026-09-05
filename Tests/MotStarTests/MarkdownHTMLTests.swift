import XCTest
@testable import MotStar

final class MarkdownHTMLTests: XCTestCase {

    func testRendersHeadingsParagraphsEmphasisAndCode() {
        let html = MarkdownHTML.document(markdown: "# Title\n\nSome **bold** and `inline code` text.")
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<code>inline code</code>"))
        XCTAssertTrue(html.contains("<p>"))
    }

    func testRendersFencedCodeBlock() {
        let html = MarkdownHTML.document(markdown: "```swift\nlet x = 1\n```")
        XCTAssertTrue(html.contains("<pre><code"))
        XCTAssertTrue(html.contains("language-swift"))
    }

    func testRendersListsAndLinks() {
        let md = """
        - one
        - two

        [link](https://example.com)
        """
        let html = MarkdownHTML.document(markdown: md)
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>"))
        XCTAssertTrue(html.contains(">one<"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">link</a>"))
    }

    func testRendersTables() {
        let md = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let html = MarkdownHTML.document(markdown: md)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>"))
        XCTAssertTrue(html.contains("<td>"))
    }

    func testOutputIsCompleteDocumentWithStylesheet() {
        let html = MarkdownHTML.document(markdown: "hello")
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.hasSuffix("</html>"))
    }

    func testLoadsFileUtf8() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("note.md")
        try "# Hello".write(to: url, atomically: true, encoding: .utf8)

        let html = MarkdownHTML.document(from: url)
        XCTAssertNotNil(html)
        XCTAssertTrue(html!.contains("<h1>Hello</h1>"))
    }
}

final class ImageRewritingTests: XCTestCase {

    private func makeBaseDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testEmbedsExistingRelativeImageAsDataURI() throws {
        let dir = try makeBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let img = dir.appendingPathComponent("pic.png")
        try Data("png".utf8).write(to: img)

        let html = #"<p>See <img src="pic.png" title="x" /> now</p>"#
        let out = MarkdownHTML.rewritingRelativeImages(html, baseDirectory: dir)

        XCTAssertTrue(out.contains("data:image/png;base64,"))
        XCTAssertFalse(out.contains(#"src="pic.png""#))
        XCTAssertTrue(out.contains("title=\"x\""))
    }

    func testLeavesMissingAndAbsoluteSourcesUntouched() throws {
        let dir = try makeBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let html = "<img src=\"missing.png\" /><img src=\"https://example.com/a.png\" /><img src=\"#frag\" />"
        let out = MarkdownHTML.rewritingRelativeImages(html, baseDirectory: dir)
        XCTAssertTrue(out.contains("src=\"missing.png\""))
        XCTAssertTrue(out.contains("src=\"https://example.com/a.png\""))
        XCTAssertTrue(out.contains("src=\"#frag\""))
    }

    func testIgnoresParentTraversal() throws {
        let dir = try makeBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let html = #"<img src="../secret.png" />"#
        let out = MarkdownHTML.rewritingRelativeImages(html, baseDirectory: dir)
        XCTAssertTrue(out.contains(#"src="../secret.png""#))
    }
}

final class TextHTMLTests: XCTestCase {
    func testEscapesMarkupAndWrapsPre() {
        let html = TextHTML.document(text: "a < b & c > d")
        XCTAssertTrue(html.contains("a &lt; b &amp; c &gt; d"))
        XCTAssertTrue(html.contains("<pre>"))
        XCTAssertTrue(html.contains("@page"))
    }
}

final class FootnoteTests: XCTestCase {
    func testRewritesReferencesAndBuildsSection() {
        let md = "Text with a note[^1] and more.[^b]\n\n[^1]: First footnote.\n\n[^b]: Second one.\n"
        let out = MarkdownHTML.applyFootnotes(md)
        XCTAssertTrue(out.contains(##"<sup class="footnote-ref"><a href="#fn-1">1</a></sup>"##))
        XCTAssertTrue(out.contains(##"<sup class="footnote-ref"><a href="#fn-b">2</a></sup>"##))
        XCTAssertTrue(out.contains(#"<li id="fn-1">First footnote."#))
        XCTAssertTrue(out.contains(#"<li id="fn-b">Second one."#))
        XCTAssertTrue(out.contains(#"<div class="footnotes">"#))
        // Definition lines are removed from the body
        XCTAssertFalse(out.contains("[^1]: First"))
    }

    func testLeavesFencedCodeUntouched() {
        let md = "```\n[^x]: not a footnote\n```\n\n[^y]: real one\n"
        let out = MarkdownHTML.applyFootnotes(md)
        XCTAssertTrue(out.contains("[^x]: not a footnote"))
        XCTAssertFalse(out.contains("[^y]: real one"))
    }
}

final class WikiAndDefinitionListTests: XCTestCase {

    private func makeDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testWikilinkResolvesToExistingNote() throws {
        let dir = try makeDir("wiki")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("# Note".utf8).write(to: dir.appendingPathComponent("target.md"))

        let out = MarkdownHTML.applyWikilinks("See [[target]] and [[other|Alias]]",
                                              baseDirectory: dir, wikilinkRoots: [dir])
        XCTAssertTrue(out.contains(#"<a class="motstar-wikilink" data-path=""#))
        XCTAssertTrue(out.contains(">target</a>"))
        XCTAssertTrue(out.contains(#"class="motstar-wikilink missing">Alias</span>"#))
        XCTAssertTrue(out.contains(#"class="motstar-wikilink missing""#))
    }

    func testWikilinkEmbedEmbedsExistingImage() throws {
        let dir = try makeDir("wikiembed")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("png".utf8).write(to: dir.appendingPathComponent("pic.png"))
        let md = "![[pic.png]]"
        let out = MarkdownHTML.applyWikilinks(md, baseDirectory: dir, wikilinkRoots: [dir])
        XCTAssertTrue(out.contains("data:image/png;base64,"))
    }

    func testDefinitionList() {
        let md = "Term one\n: definition of term one\n: another definition\n\nNormal para"
        let out = MarkdownHTML.applyDefinitionLists(md)
        XCTAssertTrue(out.contains("<dl>"))
        XCTAssertTrue(out.contains("<dt>Term one</dt>"))
        XCTAssertTrue(out.contains("<dd>definition of term one</dd>"))
        XCTAssertFalse(out.contains(": definition"))
    }
}

final class AbsoluteImageEmbedTests: XCTestCase {
    func testEmbedsAbsolutePathImage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let img = dir.appendingPathComponent("abs.png")
        try Data("png".utf8).write(to: img)

        let base = dir.appendingPathComponent("docs")
        let html = "<img src=\"\(img.path)\" />"
        let out = MarkdownHTML.rewritingRelativeImages(html, baseDirectory: base)
        XCTAssertTrue(out.contains("data:image/png;base64,"))
        XCTAssertFalse(out.contains("src=\"\(img.path)\""))
    }
}
