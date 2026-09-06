import Foundation

/// One heading in the current Markdown document.
///
/// `line` is the 1-based source line of the heading marker; it doubles as the
/// stable identity for SwiftUI list diffing. Rows are produced in document
/// order, which matches the order of `<h1>…<h6>` elements in the rendered
/// preview, so row *index* can drive preview scrolling.
struct OutlineHeading: Identifiable, Equatable {
    let id: Int
    let line: Int
    let level: Int   // 1...6
    let text: String

    init(line: Int, level: Int, text: String) {
        self.id = line
        self.line = line
        self.level = level
        self.text = text
    }
}

/// Lightweight heading outline for the document-outline pane.
///
/// Mirrors the preview's heading order: ATX headings (`#`–`######`) and
/// setext headings (`Title` + `===` / `---`), with fenced code blocks skipped
/// so the row order lines up with the preview's heading elements. Display
/// text is cleaned of the trailing ATX closing hashes and inline formatting
/// markers (`**`, `` ` ``, `~~`, `__`).
enum MarkdownOutline {

    static func parse(_ markdown: String) -> [OutlineHeading] {
        guard !markdown.isEmpty else { return [] }

        var result: [OutlineHeading] = []
        var inFence = false
        var pendingSetext: (text: String, line: Int)?
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inFence {
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    inFence = false
                }
                pendingSetext = nil
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence = true
                pendingSetext = nil
                continue
            }

            // Setext underline: "Title" then "===" (h1) or "---" (h2).
            if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "=" || $0 == "-" }) {
                if let title = pendingSetext {
                    let level = trimmed.first == "=" ? 1 : 2
                    result.append(OutlineHeading(line: title.line, level: level, text: title.text))
                }
                pendingSetext = nil
                continue
            }

            if let heading = atxHeading(in: line, lineNumber: lineNumber) {
                result.append(heading)
                pendingSetext = nil
                continue
            }

            // Track a potential setext title (plain paragraph line only).
            if trimmed.isEmpty
                || trimmed.hasPrefix("#")
                || trimmed.hasPrefix(">")
                || trimmed.hasPrefix("- ")
                || trimmed.hasPrefix("* ")
                || trimmed.hasPrefix("+ ")
                || trimmed.hasPrefix("    ")
                || trimmed.hasPrefix("\t")
                || trimmed.range(of: #"^\d+[.)]"#, options: .regularExpression) != nil {
                pendingSetext = nil
            } else {
                pendingSetext = (cleanedDisplayText(trimmed), lineNumber)
            }
        }
        return result
    }

    // MARK: Parsing helpers

    private static func atxHeading(in line: String, lineNumber: Int) -> OutlineHeading? {
        let trimmedLeft = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmedLeft.first == "#" else { return nil }

        var rest = trimmedLeft[...]
        var level = 0
        while rest.first == "#" {
            level += 1
            rest = rest.dropFirst()
        }
        guard level >= 1, level <= 6 else { return nil }
        // "###" must be followed by whitespace or end of line ("###x" is not a heading).
        if let next = rest.first, next != " " && next != "\t" { return nil }
        let content = rest.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return OutlineHeading(line: lineNumber, level: level, text: cleanedDisplayText(content))
    }

    /// Strips the closing ATX hashes ("Heading ##" → "Heading") and common
    /// inline formatting markers for a readable outline label.
    static func cleanedDisplayText(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)

        if s.hasSuffix("#") {
            var hashStart = s.endIndex
            while hashStart > s.startIndex {
                let before = s.index(before: hashStart)
                if s[before] == "#" {
                    hashStart = before
                } else {
                    break
                }
            }
            let beforeRun = hashStart > s.startIndex ? s.index(before: hashStart) : nil
            if let beforeRun, s[beforeRun] == " " {
                s = String(s[..<beforeRun]).trimmingCharacters(in: .whitespaces)
            }
        }

        for marker in ["**", "__", "~~", "`"] {
            s = s.replacingOccurrences(of: marker, with: "")
        }
        return s
    }
}
