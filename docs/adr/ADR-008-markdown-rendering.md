# ADR-008: Neat Markdown Rendering via swift-markdown + Offline WKWebView

**Status:** Accepted

**Context:**
FR-9 requires `.md` files to be *rendered* in the preview pane. The v1
`AttributedString(markdown:)` renderer (ADR-004) styles only basic inline
markup and falls short of "neat": no styled headings hierarchy, fenced-code
blocks, task lists, tables or block quotes rendered cleanly. The user asked
for neat formatted output plus a way to view the raw Markdown source.

**Decision:**
Render formatted Markdown with Apple's **swift-markdown** package (a
compile-time dependency, no runtime/network cost) parsed to HTML via its
`HTMLFormatter`, then display in an **offline `WKWebView`** with a bundled
stylesheet (system fonts, light/dark adaptive, styled headings, code blocks,
block quotes, tables, images). A **Formatted / Raw** segmented toggle in the
preview toolbar switches between the rendered view and the raw source
(monospaced, selectable).

Safety posture for the web view:
- `allowsContentJavaScript = false` — nothing in the document can execute.
- Link clicks are intercepted and opened in the default browser.
- Local images referenced by the document are embedded as **base64 data
  URIs** at render time (≤ 25 MB each; parent traversal refused). An in-app
  WebKit probe (`MOTSTAR_IMGCHECK=1`) proved pages loaded via
  `loadHTMLString` cannot fetch any local file (absolute `file://` or
  relative-with-base-URL both fail) while data URIs render — so embedding is
  the only reliable offline path, in both the preview and the PDF export.
- The page is displayed via `loadHTMLString`, and any load failure shows a
  visible error page rather than a silent blank pane. (An initial
  implementation using a temp HTML file + `loadFileURL(_:allowingReadAccessTo:)`
  produced blank previews because the main resource sat outside the granted
  read-access directory; it was replaced for this reason.)

**Consequences:**
- ✅ Truly neat rendering of the CommonMark feature set — headings, lists,
  fenced code, tables, block quotes, images, task lists.
- ✅ Zero runtime dependencies and fully offline rendering.
- ⚠️ Adds one Swift package dependency (Apple-maintained); build-time fetch
  only.
- ⚠️ Raw HTML blocks inside Markdown pass through; mitigated by JS-off +
  link interception.
- ⚠️ Supersedes the ADR-004 roadmap item "richer Markdown renderer".

**Alternatives considered:**
1. `AttributedString(markdown:)` scaled/font-patched — rejected: cannot style
   code-block backgrounds or render tables cleanly.
2. Bundled JS Markdown library (marked/highlight.js) in WKWebView —
   rejected: offline asset bundling burden, larger attack surface.
3. swift-markdown AST → custom SwiftUI block renderer — viable but much more
   code for tables/task lists; web rendering is more faithful.
