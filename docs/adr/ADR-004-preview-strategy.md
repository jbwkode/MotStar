# ADR-004: Quick Look for Non-Text Previews; Native Markdown Rendering

**Status:** Accepted

**Context:**
FR-9/FR-10: `.md` must be *rendered*; `.txt` shown as text; PDF, DOCX, PPTX,
XLSX, JPG and PNG previewed in the right pane. Rendering Office formats
faithfully from scratch is a large engineering effort.

**Decision:**
- `.md` → parse with `AttributedString(markdown:)` and display styled in
  SwiftUI `Text` (headings, emphasis, code, links). 
- `.txt` → plain monospaced text.
- Everything else (PDF, DOCX, PPTX, XLSX, JPG, PNG, and unknown types per
  accepted Q3) → `QLPreviewView` (Quick Look) wrapped in `NSViewRepresentable`,
  the system's own faithful renderer for these formats.

**Consequences:**
- ✅ Zero third-party dependencies; Office/PDF/image fidelity is Apple's own.
- ✅ Quick Look also future-proofs unknown formats (Q3).
- ⚠️ `AttributedString` Markdown is basic (no tables/fenced-code styling).
  Roadmap: swift-markdown AST renderer or bundled offline renderer.
- ⚠️ Quick Look needs a file URL and a live view; fine for single-file
  previews.

**Alternatives considered:**
1. WKWebView + JS Markdown + client-side Office viewers — rejected: heavy,
  offline bundling burden, inconsistent fidelity.
2. Third-party Swift Markdown renderers (e.g. Ink, MarkdownUI) — rejected for
  v1 zero-dependency goal; candidate for the roadmap.
3. NSAttributedString-based DOCX import — rejected: partial support at best.
