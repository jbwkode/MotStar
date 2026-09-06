import SwiftUI
import WebKit

/// Read-only, syntax-highlighted viewer for source-code files.
///
/// Renders the file through `CodeHTML` (escaped text + bundled highlight.js)
/// in an offline WKWebView, so code reads like code. Font size follows the
/// app's reading size (A−/A+, ⌘+ / ⌘− re-render at the new size).
struct CodePreviewView: NSViewRepresentable {
    let url: URL
    var textSize: Double = CodeHTML.defaultFontSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        load(url: url, textSize: textSize, into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let reloadNeeded = coordinator.lastLoadedPath != url.path || coordinator.lastFontSize != textSize
        guard reloadNeeded else { return }
        load(url: url, textSize: textSize, into: webView, coordinator: coordinator)
    }

    private func load(url: URL, textSize: Double, into webView: WKWebView, coordinator: Coordinator) {
        guard let text = MarkdownHTML.readText(url) else {
            coordinator.lastLoadedPath = url.path
            coordinator.lastFontSize = textSize
            coordinator.showUnreadable(in: webView)
            return
        }
        coordinator.lastLoadedPath = url.path
        coordinator.lastFontSize = textSize
        webView.loadHTMLString(CodeHTML.document(text: text, fontSize: textSize), baseURL: nil)
    }

    final class Coordinator {
        var lastLoadedPath: String?
        var lastFontSize: Double = CodeHTML.defaultFontSize

        func showUnreadable(in webView: WKWebView) {
            let page = """
            <html><body style="font-family:-apple-system,sans-serif;color:#888;padding:24px;">
            <p>This file could not be read as text.</p></body></html>
            """
            webView.loadHTMLString(page, baseURL: nil)
        }
    }
}
