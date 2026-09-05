import AppKit
import WebKit
import ImageIO
import UniformTypeIdentifiers

/// Diagnostic: verifies whether WKWebView pages created via `loadHTMLString`
/// can display local images, across three loading strategies. Runs only when
/// the `MOTSTAR_IMGCHECK=1` environment variable is set, then writes results
/// to /tmp/motstar-imgcheck.json. Harmless in normal operation.
enum WebKitImageProbe {

    private static let resultsFile = "/tmp/motstar-imgcheck.json"

    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["MOTSTAR_IMGCHECK"] == "1" else { return }
        Task { @MainActor in
            let results = await runAll()
            write(results)
            NSLog("MotStar imgcheck: %@", results.description)
            exit(0)
        }
    }

    // MARK: Probe body

    @MainActor
    private static func runAll() async -> [[String: Any]] {
        let dir = URL(fileURLWithPath: "/tmp/motstar-imgprobe")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let imageURL = dir.appendingPathComponent("pic.png")
        makeFixturePNG(at: imageURL)

        let dataURI = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

        var results: [[String: Any]] = []
        // Control: data URI must always load (validates the probe itself).
        results.append(await probe("control-data-uri",
                                   html: "<html><body><img src=\"\(dataURI)\" /></body></html>",
                                   baseURL: nil))
        // A) absolute file:// src, no base URL  (current implementation)
        results.append(await probe("absolute-file-no-base",
                                   html: "<html><body><img src=\"\(imageURL.absoluteString)\" /></body></html>",
                                   baseURL: nil))
        // B) relative src + file base URL
        results.append(await probe("relative-with-file-base",
                                   html: "<html><body><img src=\"pic.png\" /></body></html>",
                                   baseURL: dir))
        // C) relative src, no base URL (negative control)
        results.append(await probe("relative-no-base",
                                   html: "<html><body><img src=\"pic.png\" /></body></html>",
                                   baseURL: nil))
        // D) real pipeline: MarkdownHTML rewrites to a base64 data URI
        let raw = "<html><body><img src=\"pic.png\" /></body></html>"
        let rewritten = MarkdownHTML.rewritingRelativeImages(raw, baseDirectory: dir)
        results.append(await probe("real-rewrite-data-uri", html: rewritten, baseURL: nil))
        return results
    }

    @MainActor
    private static func probe(_ mode: String, html: String, baseURL: URL?) async -> [String: Any] {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                configuration: config)
        let waiter = LoadWaiter(webView: webView)
        webView.loadHTMLString(html, baseURL: baseURL)

        var summary: [String: Any] = ["mode": mode]
        do {
            try await waiter.wait(timeoutNanoseconds: 10_000_000_000)
            try await Task.sleep(nanoseconds: 800_000_000)
            let js = "JSON.stringify(Array.from(document.images).map(function(i){return {w:i.naturalWidth, complete:i.complete}}))"
            let value = try await webView.evaluateJavaScript(js)
            summary["images"] = value
            summary["loaded"] = true
        } catch {
            summary["loaded"] = false
            summary["error"] = error.localizedDescription
        }
        NSLog("MotStar imgcheck %@", summary.description)
        return summary
    }

    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        private weak var webView: WKWebView?
        private var continuation: CheckedContinuation<Void, Error>?
        private var finished = false

        init(webView: WKWebView) {
            self.webView = webView
            super.init()
            webView.navigationDelegate = self
        }

        func wait(timeoutNanoseconds: UInt64) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                if self.finished {
                    self.finish()
                    return
                }
                Task {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    if !self.finished { self.finish(throwing: WebKitImageProbeError.timedOut) }
                }
            }
        }

        private func finish(throwing error: Error? = nil) {
            guard !finished else { return }
            finished = true
            webView?.navigationDelegate = nil
            continuation?.resume(with: error.map(Result.failure) ?? .success(()))
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(throwing: error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(throwing: error) }
    }

    private enum WebKitImageProbeError: Error { case timedOut }

    // MARK: Fixture + output

    private static func makeFixturePNG(at url: URL) {
        let size = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = ctx.makeImage() else { return }

        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        guard let destination else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private static func write(_ results: [[String: Any]]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: resultsFile))
            NSLog("MotStar imgcheck wrote %@", resultsFile)
        } catch {
            NSLog("MotStar imgcheck write failed: %@", error.localizedDescription)
        }
    }
}
