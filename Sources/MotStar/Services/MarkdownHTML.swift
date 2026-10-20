import Foundation
import Markdown
import UniformTypeIdentifiers

/// Renders Markdown to a self-contained HTML document (offline, no network)
/// using Apple's swift-markdown AST → HTML formatter (ADR-008), enhanced by
/// bundled client-side runtimes (ADR-009/Phase 2):
///  - local images embedded as base64 data URIs
///  - Mermaid diagrams (web/mermaid.min.js)
///  - KaTeX maths (web/katex.min.js + web/katex-embed.css with data-URI fonts)
///  - syntax highlighting (web/highlight.min.js)
///  - GFM-style footnotes (pre-pass), bare-URL autolinks + emoji shortcodes +
///    Obsidian callouts (web/phase2-runner.js + web/emoji.json)
enum MarkdownHTML {

    // MARK: Public entry points

    /// Plain Markdown → HTML (lightweight; no client runtimes). Test/utility
    /// call sites only.
    static func document(markdown: String) -> String {
        return template(body: HTMLFormatter.format(markdown), enriched: false)
    }

    /// Markdown → enriched HTML resolved against a base folder (preview,
    /// print and PDF export): images embedded, footnotes processed, and the
    /// bundled KaTeX/Mermaid/highlight/emoji/linkify runtimes inlined.
    /// `wikilinkRoots` (Obsidian-style vault folders) enable `[[note]]`
    /// links and `![[image.png]]` embeds. `baseFontSize` scales the body
    /// text (headings are em-based, so they scale proportionally).
    static func document(markdown: String, baseDirectory: URL, wikilinkRoots: [URL] = [], baseFontSize: Double = defaultReadingFontSize) -> String {
        var enhanced = markdown
        enhanced = applyFootnotes(enhanced)
        enhanced = applyWikilinks(enhanced, baseDirectory: baseDirectory, wikilinkRoots: wikilinkRoots)
        enhanced = applyDefinitionLists(enhanced)
        let body = rewritingRelativeImages(HTMLFormatter.format(enhanced), baseDirectory: baseDirectory)
        return template(body: body, enriched: true, baseFontSize: baseFontSize)
    }

    /// Load a `.md` file (UTF-8, else UTF-16) and render it for display.
    static func document(from url: URL) -> String? {
        guard let text = readText(url) else { return nil }
        return document(markdown: text, baseDirectory: url.deletingLastPathComponent())
    }

    /// Body font size (CSS px) used when no explicit size is requested.
    /// Kept in sync with `AppState.readingFontSize`'s default.
    static let defaultReadingFontSize: Double = 15

    static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
    }

    // MARK: GFM-style footnotes (pre-parse pass)

    /// Rewrites `[^key]` references into numbered footnote links and moves
    /// `[^key]: …` definitions into a footnotes section at the end. Line-based
    /// and heuristic: fenced code blocks and indented blocks are skipped.
    static func applyFootnotes(_ markdown: String) -> String {
        let pattern = try? NSRegularExpression(pattern: #"\[\^([A-Za-z0-9_\-]+)\]"#)
        let defPattern = try? NSRegularExpression(pattern: #"^\[\^([A-Za-z0-9_\-]+)\]:\s*(.*)$"#)

        let lines = markdown.components(separatedBy: "\n")
        var references: [String: Int] = [:]
        var definitions: [(key: String, text: String)] = []
        var nextNumber = 1
        var inFence = false
        var output: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                output.append(line)
                continue
            }
            if inFence || trimmed.isEmpty || line.hasPrefix("    ") || line.hasPrefix("\t") {
                output.append(line)
                continue
            }
            if let defPattern, let match = defPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
                let key = String(trimmed[Range(match.range(at: 1), in: trimmed)!])
                let text = String(trimmed[Range(match.range(at: 2), in: trimmed)!])
                definitions.append((key, text))
                continue
            }
            guard let pattern else {
                output.append(line)
                continue
            }
            var replaced = ""
            var cursor = line.startIndex
            for match in pattern.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                let whole = Range(match.range(at: 0), in: line)!
                let key = String(line[Range(match.range(at: 1), in: line)!])
                replaced += line[cursor..<whole.lowerBound]
                let number: Int
                if let existing = references[key] {
                    number = existing
                } else {
                    number = nextNumber
                    references[key] = number
                    nextNumber += 1
                }
                replaced += "<sup class=\"footnote-ref\"><a href=\"#fn-\(key)\">\(number)</a></sup>"
                cursor = whole.upperBound
            }
            replaced += line[cursor...]
            output.append(replaced)
        }

        guard !definitions.isEmpty else { return output.joined(separator: "\n") }

        var footer = "\n\n<div class=\"footnotes\">\n<hr>\n<ol>\n"
        for definition in definitions {
            _ = references[definition.key] ?? {
                let n = nextNumber
                nextNumber += 1
                return n
            }()
            footer += "<li id=\"fn-\(definition.key)\">\(escapeHTML(definition.text)) <a href=\"#fn-\(definition.key)\" class=\"footnote-back\">↩︎</a></li>\n"
        }
        footer += "</ol>\n</div>\n"
        return output.joined(separator: "\n") + footer
    }

    private static func escapeHTML(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: Wikilinks & embeds (Obsidian-style)

    /// Rewrites `[[target]]` / `[[target|alias]]` into app links and
    /// `![[image.png|alt]]` into embedded images. Resolution order: relative
    /// to the document folder, then each wikilink root; `.md` is implied for
    /// links without an extension. Fenced code is skipped.
    static func applyWikilinks(_ markdown: String, baseDirectory: URL, wikilinkRoots: [URL]) -> String {
        guard !wikilinkRoots.isEmpty else { return markdown }
        let pattern = try? NSRegularExpression(pattern: #"!?\[\[([^\[\]|]+)(?:\|([^\[\]]+))?\]\]"#)
        guard let pattern else { return markdown }

        var inFence = false
        var output: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                output.append(line)
                continue
            }
            if inFence || trimmed.hasPrefix("    ") || trimmed.hasPrefix("\t") {
                output.append(line)
                continue
            }
            guard let pattern = pattern as NSRegularExpression? else {
                output.append(line)
                continue
            }
            var replaced = ""
            var cursor = line.startIndex
            let matches = pattern.matches(in: line, range: NSRange(line.startIndex..., in: line))
            for match in matches {
                let whole = Range(match.range(at: 0), in: line)!
                let isEmbed = line[whole.lowerBound] == "!"
                let name = String(line[Range(match.range(at: 1), in: line)!]).trimmingCharacters(in: .whitespaces)
                let label = match.range(at: 2).location != NSNotFound
                    ? String(line[Range(match.range(at: 2), in: line)!])
                    : nil

                replaced += line[cursor..<whole.lowerBound]
                if isEmbed {
                    replaced += embedHTML(name: name, alt: label, baseDirectory: baseDirectory, roots: wikilinkRoots)
                } else {
                    replaced += linkHTML(name: name, alias: label, baseDirectory: baseDirectory, roots: wikilinkRoots)
                }
                cursor = whole.upperBound
            }
            replaced += line[cursor...]
            output.append(replaced)
        }
        return output.joined(separator: "\n")
    }

    private static func resolveWiki(_ name: String, baseDirectory: URL, roots: [URL], isImage: Bool) -> URL? {
        var candidates: [URL] = []
        func add(_ base: URL) {
            let target = base.appendingPathComponent(name).standardizedFileURL
            candidates.append(target)
            if !isImage && target.pathExtension.isEmpty {
                candidates.append(base.appendingPathComponent(name + ".md").standardizedFileURL)
            }
        }
        add(baseDirectory)
        for root in roots where root != baseDirectory { add(root) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func linkHTML(name: String, alias: String?, baseDirectory: URL, roots: [URL]) -> String {
        let cleanName = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        if let target = resolveWiki(name, baseDirectory: baseDirectory, roots: roots, isImage: false) {
            let label = escapeHTML(alias ?? cleanName)
            let path = escapeHTML(target.path)
            return "<a class=\"motstar-wikilink\" data-path=\"\(path)\">\(label)</a>"
        }
        let label = escapeHTML(alias ?? cleanName)
        return "<span class=\"motstar-wikilink missing\">\(label)</span>"
    }

    private static func embedHTML(name: String, alt: String?, baseDirectory: URL, roots: [URL]) -> String {
        guard let target = resolveWiki(name, baseDirectory: baseDirectory, roots: roots, isImage: true) else {
            return ""
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
        guard let size = (attributes?[.size] as? NSNumber)?.intValue,
              size > 0, size <= maxEmbeddedImageBytes,
              let data = try? Data(contentsOf: target) else { return "" }
        let mime = UTType(filenameExtension: target.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let altText = escapeHTML(alt ?? target.lastPathComponent)
        return "<img src=\"data:\(mime);base64,\(data.base64EncodedString())\" alt=\"\(altText)\">"
    }

    // MARK: Definition lists

    /// Converts `Term` + `: definition` lines into a `<dl>` list. Heuristic:
    /// a plain line followed by one or more `: ` lines, outside fenced code.
    static func applyDefinitionLists(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var output: [String] = []
        var i = 0
        var inFence = false

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                output.append(line)
                i += 1
                continue
            }
            // Look ahead: term followed by ": " definitions?
            if !inFence, !trimmed.isEmpty, !trimmed.hasPrefix(":"), i + 1 < lines.count,
               lines[i + 1].hasPrefix(": ") || lines[i + 1] == ":" {
                let term = trimmed
                var items: [String] = []
                var j = i + 1
                while j < lines.count, lines[j].hasPrefix(":") {
                    let def = lines[j].hasPrefix(": ") ? String(lines[j].dropFirst(2)) : ""
                    if !def.isEmpty { items.append(def) }
                    j += 1
                }
                var html = "<dl>\n<dt>\(escapeHTML(term))</dt>\n"
                for item in items {
                    html += "<dd>\(escapeHTML(item))</dd>\n"
                }
                html += "</dl>"
                output.append(html)
                i = j
                continue
            }
            output.append(line)
            i += 1
        }
        return output.joined(separator: "\n")
    }

    // MARK: Relative image resolution

    /// Rewrites `<img src="relative.png">` where the file exists (relative to
    /// the document, or an absolute POSIX path) into an inline base64 data
    /// URI (`data:<mime>;base64,…`).
    static func rewritingRelativeImages(_ html: String, baseDirectory: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"src="([^"]+)""#) else { return html }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var result = ""
        var lastIndex = html.startIndex

        for match in regex.matches(in: html, range: nsRange) {
            let whole = Range(match.range(at: 0), in: html)!
            let sourceRange = Range(match.range(at: 1), in: html)!
            let source = String(html[sourceRange])

            result += html[lastIndex..<whole.lowerBound]
            if isAbsoluteSource(source) {
                result += html[whole]
            } else if let dataURI = dataURI(for: source, in: baseDirectory) {
                result += #"src=""# + dataURI + "\""
            } else {
                result += html[whole]
            }
            lastIndex = whole.upperBound
        }
        result += html[lastIndex...]
        return result
    }

    static let maxEmbeddedImageBytes = 25 * 1024 * 1024
    private static func isAbsoluteSource(_ source: String) -> Bool {
        guard let first = source.first else { return true }
        let lowered = source.lowercased()
        return first == "#"
            || lowered.hasPrefix("http:")
            || lowered.hasPrefix("https:")
            || lowered.hasPrefix("file:")
            || lowered.hasPrefix("data:")
            || lowered.hasPrefix("//")
    }

    private static func dataURI(for source: String, in directory: URL) -> String? {
        let cleaned = source.removingPercentEncoding ?? source

        let target: URL
        if cleaned.hasPrefix("/") {
            target = URL(fileURLWithPath: cleaned).standardizedFileURL
        } else {
            guard !cleaned.contains("..") else { return nil } // no parent traversal
            target = directory.appendingPathComponent(cleaned).standardizedFileURL
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
        guard let size = (attributes?[.size] as? NSNumber)?.intValue,
              size > 0, size <= maxEmbeddedImageBytes else { return nil }

        guard let data = try? Data(contentsOf: target) else { return nil }
        let mime = UTType(filenameExtension: target.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
    // MARK: Web resource loading (bundle → SwiftPM bundle)

    private static var resourceCache: [String: String] = [:]

    static func webResource(named name: String) -> String? {
        if let cached = resourceCache[name] { return cached }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        // The release .app (scripts/bundle-app.sh) copies the web assets straight
        // into Contents/Resources/web, so Bundle.main is authoritative there.
        // `swift run` / Xcode SPM builds instead nest them in the generated
        // "MotStar_MotStar.bundle". That bundle is located manually below:
        // referencing the synthesized Bundle.module would trap (fatalError)
        // because the resource bundle is NOT shipped inside the .app.
        var url = Bundle.main.url(forResource: stem, withExtension: ext, subdirectory: "web")
        if url == nil {
            url = spmResourceBundleURL(forResource: stem, withExtension: ext, subdirectory: "web")
        }
        guard let url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Never let "</script" terminate an inline script block.
        let safe = text.replacingOccurrences(of: "</script", with: "<\\/script")
        resourceCache[name] = safe
        return safe
    }

    /// Locates a file inside the SwiftPM-processed resource bundle
    /// (`<Package>_<Target>.bundle`) without touching the synthesized
    /// `Bundle.module`, which traps when that bundle is absent (as in the
    /// packaged .app — see `webResource(named:)` above).
    private static func spmResourceBundleURL(forResource stem: String, withExtension ext: String, subdirectory: String?) -> URL? {
        let bundleName = "MotStar_MotStar.bundle"
        let bases = [
            Bundle.main.resourceURL,
            Bundle.main.executableURL?.deletingLastPathComponent()
        ].compactMap { $0 }
        for base in bases {
            let bundleURL = base.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: stem, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }

    private static var katexCSS: String? { webResource(named: "katex-embed.css") }
    private static var katexJS: String? { webResource(named: "katex.min.js") }
    private static var mermaidJS: String? { webResource(named: "mermaid.min.js") }
    private static var highlightJS: String? { webResource(named: "highlight.min.js") }
    private static var runnerJS: String? { webResource(named: "phase2-runner.js") }
    private static var emojiJSON: String? { webResource(named: "emoji.json") }

    // MARK: Template

    private static func baseCSS(fontSize: Double) -> String {
        """
    :root { color-scheme: light dark; }
    body {
        margin: 0;
        padding: 24px 30px 60px;
        font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
        font-size: \(Int(fontSize))px;
        line-height: 1.65;
        color: #1d1d1f;
        background: #ffffff;
        overflow-wrap: break-word;
        -webkit-font-smoothing: antialiased;
    }
    h1, h2, h3, h4 { line-height: 1.3; margin: 1.4em 0 0.45em; font-weight: 600; }
    h1 { font-size: 1.75em; padding-bottom: 0.25em; border-bottom: 1px solid rgba(127, 127, 127, 0.3); }
    h2 { font-size: 1.45em; padding-bottom: 0.2em; border-bottom: 1px solid rgba(127, 127, 127, 0.2); }
    h3 { font-size: 1.2em; }
    h4 { font-size: 1.05em; }
    p { margin: 0.6em 0; }
    a { color: #0a66dc; text-decoration: none; }
    a:hover { text-decoration: underline; }
    ul, ol { padding-left: 1.6em; margin: 0.6em 0; }
    li { margin: 0.25em 0; }
    li > ul, li > ol { margin: 0.15em 0; }
    blockquote {
        margin: 0.8em 0;
        padding: 0.2em 1.1em;
        border-left: 3px solid rgba(127, 127, 127, 0.45);
        color: #4a4a52;
    }
    code {
        font-family: ui-monospace, 'SF Mono', Menlo, Consolas, monospace;
        font-size: 0.88em;
        padding: 0.12em 0.35em;
        border-radius: 4px;
        background: rgba(127, 127, 127, 0.14);
    }
    pre {
        margin: 0.9em 0;
        padding: 12px 14px;
        border-radius: 8px;
        background: rgba(127, 127, 127, 0.12);
        overflow-x: auto;
        line-height: 1.5;
    }
    pre code { background: none; padding: 0; font-size: 0.86em; }
    pre code.hljs { background: none; padding: 0; }
    hr { border: none; border-top: 1px solid rgba(127, 127, 127, 0.35); margin: 1.6em 0; }
    table { border-collapse: collapse; margin: 0.9em 0; display: block; max-width: 100%; overflow-x: auto; }
    th, td { border: 1px solid rgba(127, 127, 127, 0.35); padding: 5px 12px; text-align: left; }
    th { background: rgba(127, 127, 127, 0.12); font-weight: 600; }
    img { max-width: 100%; height: auto; }
    input[type='checkbox'] { margin-right: 6px; vertical-align: -1px; }
    aside { border-left: 3px solid rgba(127,127,127,.45); padding: 0.1em 1.1em; margin: 0.8em 0; }
    .mermaid { display: flex; justify-content: center; margin: 1.2em 0; overflow-x: auto; }
    .mermaid svg { max-width: 100%; height: auto; }
    .mermaid-error { color: #d43; font-size: 0.85em; font-family: ui-monospace, Menlo, monospace;
                     border: 1px dashed rgba(200,60,50,.5); padding: 8px 10px; border-radius: 6px; margin: .8em 0; }

    /* Syntax highlighting (GitHub-like light) */
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

    /* Callouts */
    blockquote.motstar-callout {
        border-left-width: 4px;
        border-radius: 6px;
        padding: 0.55em 1.1em 0.55em 1em;
        margin: 1em 0;
        background: rgba(127, 127, 127, 0.06);
    }
    .callout-title { font-weight: 600; margin-bottom: 0.3em; }

    /* KaTeX display */
    .katex-display { overflow-x: auto; overflow-y: hidden; padding: 4px 0; }
    .math-display, .math-display-inline { display: block; overflow-x: auto; margin: 0.8em 0; }

    /* Footnotes */
    .footnote-ref { font-size: 0.72em; vertical-align: super; }
    .footnote-ref a { text-decoration: none; }
    .footnotes { font-size: 0.86em; color: #4a4a52; margin-top: 1.6em; }
    .footnotes hr { margin: 1em 0; }
    .footnotes ol { padding-left: 1.4em; }
    .footnotes li { margin: 0.35em 0; }
    .footnote-back { text-decoration: none; }

    /* Wikilinks, tags, definition lists */
    a.motstar-wikilink { color: #0969da; text-decoration: underline; text-decoration-style: dotted; }
    .motstar-wikilink.missing { color: #d43; text-decoration: underline; text-decoration-style: dotted; }
    .motstar-tag { color: #8250df; font-size: 0.88em; }
    dl { margin: 0.8em 0; }
    dt { font-weight: 600; }
    dd { margin: 0.15em 0 0.5em 1.4em; color: #4a4a52; }

    @media (prefers-color-scheme: dark) {
        body { color: #e9e9ee; background: #1e1e22; }
        blockquote { color: #b6b6c0; }
        a { color: #6cb2ff; }
        .mermaid-error { color: #ff8a80; }
        a.motstar-wikilink { color: #6cb2ff; }
        .motstar-wikilink.missing { color: #ff8a80; }
        .motstar-tag { color: #d2a8ff; }
        dd { color: #b6b6c0; }
        .hljs-comment, .hljs-quote { color: #8b949e; }
        .hljs-keyword, .hljs-selector-tag, .hljs-subst { color: #ff7b72; }
        .hljs-string, .hljs-doctag, .hljs-addition { color: #a5d6ff; }
        .hljs-number, .hljs-literal, .hljs-attr { color: #79c0ff; }
        .hljs-title, .hljs-section, .hljs-name, .hljs-type, .hljs-built_in { color: #d2a8ff; }
        .hljs-meta, .hljs-symbol, .hljs-link { color: #a5d6ff; }
        .footnotes { color: #b6b6c0; }
    }

    @media print {
        /* WebKit's PDF generator ignores @page margins, so print padding is
           applied on the body to guarantee real page margins. */
        body { padding: 0; color: #000000; background: #ffffff; }
        a { color: #000000; text-decoration: underline; }
        pre, blockquote, th, td, code { background: transparent; }
        img { max-width: 100%; }
    }
    @page { size: A4; margin: 0; }
    """
    }

    private static func template(body: String, enriched: Bool, baseFontSize: Double = defaultReadingFontSize) -> String {
        var extraStyles = ""
        var extraScripts = ""
        if enriched {
            var libs: [String] = []
            if let katex = katexJS, katexCSS != nil {
                libs.append(katex)
                if let css = katexCSS {
                    extraStyles = "<style>\n\(css)\n</style>\n"
                }
            }
            if let mermaid = mermaidJS { libs.append(mermaid) }
            if let highlight = highlightJS { libs.append(highlight) }
            for lib in libs {
                extraScripts += "<script>\n\(lib)\n</script>\n"
            }
            if let runner = runnerJS {
                var preamble = ""
                if let emoji = emojiJSON {
                    preamble = "const EMOJI_MAP = \(emoji);\n"
                }
                extraScripts += "<script>\n\(preamble)\(runner)\n</script>\n"
            }
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(baseCSS(fontSize: baseFontSize))
        </style>
        \(extraStyles)
        </head>
        <body>
        <article>
        \(body)
        </article>
        \(extraScripts)
        </body>
        </html>
        """
    }
}
