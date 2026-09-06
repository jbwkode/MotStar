import XCTest
@testable import MotStar

final class CodeHTMLTests: XCTestCase {

    func testEscapesMarkupSoItIsNotRendered() {
        let html = CodeHTML.document(text: "let x = a < b && c > d")
        XCTAssertTrue(html.contains("a &lt; b &amp;&amp; c &gt; d"))
        XCTAssertFalse(html.contains("< b"))
    }

    func testOutputIsCompleteDocumentWithCodeBlock() {
        let html = CodeHTML.document(text: "func greet() { print(\"hi\") }")
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<pre><code>"))
        XCTAssertTrue(html.contains("</code></pre>"))
        XCTAssertTrue(html.hasSuffix("</html>"))
    }

    func testAppliesFontSizeAndBundlesHighlighterWhenAvailable() {
        let html = CodeHTML.document(text: "x", fontSize: 21)
        XCTAssertTrue(html.contains("font-size: 21px"))
        // The asset ships with the app bundle; when present it is inlined.
        if MarkdownHTML.webResource(named: "highlight.min.js") != nil {
            XCTAssertTrue(html.contains("hljs.highlightElement"))
        }
    }
}
