# MotStar Markdown & Text Editor — Feature Plan

**Version:** 0.1 (plan)
**Date:** 2026-09-05
**Reference base:** Obsidian (desktop MD editor), GitHub Flavored Markdown
(GFM), CommonMark, Mermaid. Research: markdownguide.org/extended-syntax,
swift-markdown supported constructs, mermaid.js documentation.

---

## 1. Goal

Turn MotStar's read-only previewer into a **dual-mode viewer/editor** for
Markdown (`.md`) and plain-text (`.txt`) files, able to create, edit, save
and richly render documents — inline graphics, diagrams (Mermaid), and the
full GFM surface — modelled on Obsidian's core writing experience, scoped to
what a single-window native app does well.

## 2. Editor capability inventory (from research)

### 2.1 Core editing behaviours (Obsidian-like)
- Create new `.md` / `.txt` files anywhere on disk
- Edit existing `.md` / `.txt`
- Source editing with native text view: undo/redo, ⌘S save, ⌥⌘R revert to
  saved (discard unsaved edits), dirty-dot and save/discard prompts on file
  switch, standard text editing behaviours
- Live **Preview / Edit** toggle per file; preview reflects the unsaved
  draft, and leaving the editor with unsaved changes prompts
  Save / Discard / Cancel
- Keyboard-first: ⌘N new file, ⌘S save, ⌥⌘R revert, ⌘E toggle edit/preview,
  ⌘P print, ⇧⌘E export PDF, markdown ⇧⌘R formatted/raw
- Inline image display (local, data-URI embedding — done in v0.3)

### 2.2 Markdown syntax surface to render (matrix)

| Feature | Status today (swift-markdown + HTML) | Target |
|---|---|---|
| CommonMark: headings, paragraphs, emphasis, strong, lists, links, images, code spans/fences, blockquotes, HR | ✅ | keep |
| GFM tables (alignment, cell formatting) | ✅ | keep |
| GFM task lists (checkbox list items) | ✅ | keep |
| GFM strikethrough `~~x~~` | ✅ | keep |
| GFM autolinks / bare URLs | ⚠️ partial (needs extension) | add |
| GFM footnotes `[^1]` | ⚠️ not rendered by formatter | add (Phase 2) |
| Syntax-highlighted fenced code | ⬜ plain styling only | add highlight.js (Phase 2) |
| Diagrams: **Mermaid** (` ```mermaid `) | ⬜ | ✅ this release (bundled runtime) |
| LaTeX math `$…$`, `$$…$$` | ⬜ | add KaTeX (Phase 2) |
| Emoji shortcodes `:joy:` | ⬜ | add (Phase 2, small lib) |
| HTML passthrough | ✅ (raw HTML kept) | keep, JS on (user content) |
| Definition lists / subscript / superscript / highlight `==x==` | ⬜ not GFM | optional (Phase 3, MarkdownExtra-like) |

### 2.3 Obsidian-style conveniences (Phase 2/3, scope-gated)
- **Wikilinks** `[[Note]]` + **embeds** `![[image.png]]` resolving to local
  files in the vault/root folders
- **Tags** `#topic` styling
- **Callouts/admonitions** `> [!note] …` (CSS blockquote styling)
- **Outgoing links panel**, backlinks, graph — explicitly out of scope
  (needs a vault/index model)
- **Front matter** (YAML) folding — cosmetic, Phase 3

## 3. Rendering architecture

- Formatted preview: swift-markdown → HTML → **offline WKWebView**
  (JS enabled for Mermaid; local images embedded as data URIs; link clicks
  open externally)
- Mermaid: bundled `web/mermaid.min.js` (v10 UMD, 3.3 MB, no network at
  runtime), inlined into the generated page, renders ` ```mermaid ` blocks
- Export/Print: same HTML through the print pipeline; JS enabled so diagrams
  appear in printed/exported PDFs

## 4. Delivery phases

**Phase 1 — editor core (this release):** create/save `.md`/`.txt`, source
editing, dirty tracking, Edit/Preview toggle with draft-aware preview, new
file + reveal in tree, Mermaid diagrams in preview/print/export. ✅ done

**Phase 2 — richness:** syntax highlighting (highlight.js bundled ✅),
LaTeX math (KaTeX bundled, data-URI fonts ✅), GFM footnotes ✅, bare-URL
autolinks ✅, emoji shortcodes ✅, Obsidian callouts ✅. Remaining polish:
inline-link CSS, more emoji coverage as needed.

**Phase 3 — Obsidian conveniences:** wikilinks/embeds across root folders ✅
(`[[note]]`, `![[image.png]]`, click-to-open in-app), tags styling ✅,
definition lists ✅, editor niceties: markdown format toolbar + Format menu
✅, word-wrap toggle (⌥⌘W) ✅, focus mode (⌥⌘F) ✅. Not yet: line numbers,
live split edit/preview, backlinks panel (out of scope).

## 5. Open decisions for the user

1. Editing scope: read-write for files **inside chosen folders only**, or
   any file opened from disk? (Default: any file the user selects from the
   tree.)
2. Autosave vs explicit ⌘S? (Default: explicit ⌘S + prompt on switch;
   autosave toggle later.)
3. Word wrap in source editor: on by default? (Default: on.)
