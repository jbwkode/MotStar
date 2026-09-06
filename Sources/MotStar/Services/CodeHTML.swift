import Foundation

/// Renders a plain-text source file as a self-contained, syntax-highlighted
/// HTML document (offline, no network). Reuses the bundled highlight.min.js
/// runtime so code files read like code instead of monochrome text.
///
/// The whole file is HTML-escaped and placed in a single `<pre><code>` block;
/// highlight.js auto-detects the language from the content. Font size follows
/// the app's reading size; a light/dark palette is provided via CSS.
enum CodeHTML {

    /// Default font size (pt/px) when none is given (see AppState defaults).
    static let defaultFontSize: Double = 13

    static func document(text: String, fontSize: Double = defaultFontSize) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let runner = MarkdownHTML.webResource(named: "highlight.min.js") ?? ""
        let inlineScript = runner.isEmpty
            ? ""
            : "<script>\n\(runner)\n</script>\n"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body {
            margin: 0;
            padding: 16px 20px 48px;
            font-family: ui-monospace, 'SF Mono', Menlo, Consolas, monospace;
            font-size: \(Int(fontSize))px;
            line-height: 1.55;
            color: #1d1d1f;
            background: #ffffff;
            overflow-wrap: break-word;
            -webkit-font-smoothing: antialiased;
        }
        pre {
            margin: 0;
            white-space: pre-wrap;
            word-break: break-word;
            font-family: inherit;
            font-size: inherit;
            tab-size: 4;
        }
        code { font-family: inherit; background: none; padding: 0; }
        /* GitHub-like light palette (matches the markdown preview) */
        .hljs-comment, .hljs-quote { color: #6a737d; font-style: italic; }
        .hljs-keyword, .hljs-selector-tag, .hljs-subst { color: #d73a49; }
        .hljs-string, .hljs-doctag, .hljs-regexp, .hljs-addition { color: #032f62; }
        .hljs-number, .hljs-literal, .hljs-variable, .hljs-template-variable,
        .hljs-tag .hljs-attr, .hljs-attr { color: #005cc5; }
        .hljs-title, .hljs-section, .hljs-name, .hljs-selector-id, .hljs-selector-class,
        .hljs-type, .hljs-built_in, .hljs-builtin-name, .hljs-class .hljs-title { color: #6f42c1; }
        .hljs-meta, .hljs-symbol, .hljs-bullet, .hljs-link { color: #032f62; }
        .hljs-emphasis { font-style: italic; }
        .hljs-strong { font-weight: 600; }

        @media (prefers-color-scheme: dark) {
            body { color: #e9e9ee; background: #1e1e22; }
            .hljs-comment, .hljs-quote { color: #8b949e; }
            .hljs-keyword, .hljs-selector-tag, .hljs-subst { color: #ff7b72; }
            .hljs-string, .hljs-doctag, .hljs-addition { color: #a5d6ff; }
            .hljs-number, .hljs-literal, .hljs-attr { color: #79c0ff; }
            .hljs-title, .hljs-section, .hljs-name, .hljs-type, .hljs-built_in { color: #d2a8ff; }
            .hljs-meta, .hljs-symbol, .hljs-link { color: #a5d6ff; }
        }
        </style>
        </head>
        <body>
        <pre><code>\(escaped)</code></pre>
        \(inlineScript)
        <script>
        (function(){
          var el = document.querySelector('code');
          if (el && window.hljs) { hljs.highlightElement(el); }
        })();
        </script>
        </body>
        </html>
        """
    }
}
