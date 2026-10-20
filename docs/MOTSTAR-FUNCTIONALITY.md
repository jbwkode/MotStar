# MotStar — Complete Functional Specification (for build comparison)

**Version:** 1.1 — generated 2026-09-06 from the shipped app (v0.3.10)
**Purpose:** give another AI/team everything needed to build a feature-parity
macOS app.
**Repo:** `https://github.com/jbwkode/MotStar` — source of truth.
**Platform:** native macOS 14+ (Sonoma), Apple Silicon + Intel. Swift/SwiftUI
with targeted AppKit bridges. No third-party runtime services; everything
works offline.

---

## 1. Identity

- **Name:** MotStar (display name, bundle id `com.motstar.mac`)
- **Type:** single-window, two-pane desktop document navigator + Markdown
  editor + previewer
- **Branding assets (v0.3.0):** Dock/Finder tile (`appicon-source.*`, full-
  bleed for opaque artwork), About-window logo (transparent PNG), clickable
  app-icon in the title-bar right edge that **minimizes** the window
- **Icon:** custom generated artwork; About window shows the brand logo
- **Signing:** Apple Development identity (Team `U6PYFJD9QA`) via bundle
  script; falls back to ad-hoc. Not notarized yet.

## 2. Overall architecture

- **UI toolkit:** SwiftUI; AppKit bridges where SwiftUI lacks: `NSTextView`
  source editor, `NSOpenPanel`/`NSSavePanel`, `WKWebView` preview,
  `QLPreviewView` (Quick Look), `NSAppleScript`-style events via
  `/usr/bin/osascript`, `NSSharingService`.
- **Single shared `AppState`** (`@MainActor`, `ObservableObject`, shared
  singleton): folders, tree nodes, selection, editor document, alerts,
  search, focus state. Toolbar buttons and menu commands call identical
  methods.
- **Swift Package** (executable target) — builds with `swift build`,
  `swift run`, or Xcode (open `Package.swift`).
- **Dependencies (build-time only, all bundled into the app, zero runtime
  network):**
  - `swift-markdown` 0.8.0 (Apple) — Markdown AST → HTML
  - Mermaid 10.9.1 (UMD) — diagrams, inlined at render
  - KaTeX 0.16.11 — maths, JS + stylesheet with fonts embedded as data URIs
  - highlight.js 11.9.0 — code syntax highlighting
- **Bundled web assets** (in `Sources/MotStar/Resources/web/`): inlined into
  generated HTML because WKWebView pages loaded via `loadHTMLString` cannot
  fetch any local file.

## 3. Window & layout

- One window, `NavigationSplitView`: **left = file tree**, **right =
  preview/editor** (resizable).
- Title bar: window title text suppressed; the **app icon is shown at the
  right edge and clicking it minimizes** the window to the Dock (⌘M style
  action without the shortcut).
- **Focus mode** (⌥⌘F): collapses the sidebar (`columnVisibility .detailOnly`)
  for distraction-free editing.
- **Appearance themes (Settings, ⌘,):** System / Light / Dark applied to
  every window including the Markdown preview (CSS `prefers-color-scheme`).

## 4. Left pane — folder tree

- **Root folders:** user adds folders via "Add Folder…" (folder picker,
  multiple allowed). Stored as JSON paths in `UserDefaults`
  (`navstar.rootFolders.v1` — deliberately stable across renames), restored
  on launch. Remove via right-click.
- **Recursive tree:** lazy, depth-on-demand — a folder's children are
  enumerated (background) only when first expanded. Folders first, then
  files; localized case-insensitive sort. Hidden files (`.*`) excluded.
  Missing/unreadable folders show an inline error state, never crash.
- **Expansion state** lives in `AppState` (path set) so code can expand
  programmatically (reveal after create/search).
- **Live refresh:** FSEvents watcher on all roots; external changes reload
  affected roots after ~0.7 s debounce (visible subtrees re-enumerate).
- **Rows:** folder = folder icon; file = **coloured marker dot + standard
  SF Symbol icon**. Clicking a file selects it; clicking folders toggles.
- **Sorting (configurable):** folders always alphabetical first; file
  ordering is a **Settings (⌘,)** preference — **Newest first** (default)
  or **Alphabetical (A–Z)**. Applied on every expansion/refresh.
- **Settings gear** at the bottom-right of the sidebar opens Settings.
- **Selected row** highlight in accent colour.

### File-type registry (single source of truth)

| Type | Extensions | Marker colour | SF Symbol |
|---|---|---|---|
| Markdown | `.md` `.markdown` | Indigo `#6366F1` | doc.richtext |
| Plain text | `.txt` | Grey `#9CA3AF` | doc.plaintext |
| PDF | `.pdf` | Red `#E53E3E` | doc.richtext |
| Word | `.docx` | Word blue `#2B579A` | doc.text |
| PowerPoint | `.pptx` | Orange `#D24726` | chart.bar.doc.horizontal |
| Excel | `.xlsx` | Green `#217346` | tablecells |
| Images | `.jpg .jpeg .png` | Cyan `#06B6D4` | photo |
| Other | — | Grey | doc |

Classification: case-insensitive extension first, UTI fallback. Unknown
types show with generic icon and Quick Look preview (never hidden).

## 5. Right pane — preview & editing

- **Mode picker (Markdown/text only):** `Preview | Edit` segmented control.
- **Empty state:** icon + "Select a file to preview it" + New Markdown File
  / Add Folder buttons.
- Toolbar (always when a file selected): **Share · Email · Print · Export
  PDF** (icons); for editable files the mode picker and, while editing, a
  **Save** button plus a **Revert** button (discard changes, ⌥⌘R); for
  Markdown in Preview, a **Formatted | Raw** toggle.

### Previews by type
- **Markdown (.md):** formatted HTML in offline WKWebView (default), or raw
  monospaced source toggle (⇧⌘R). Draft-aware: unsaved editor text is
  rendered, not the stale disk file.
- **Plain text:** monospaced, selectable.
- **Images (jpg/png):** dedicated view — scaled to fit pane; double-click
  toggles 1:1 (scrollable).
- **PDF/Office/other:** Quick Look (`QLPreviewView`).

### Markdown renderer features (the big one)
Pipeline: optional pre-passes → `swift-markdown` AST → HTML → CSS + bundled
runtimes inlined → offline WKWebView (JS enabled only for these generated
Markdown pages; links open in the default browser via navigation policy).

1. **CommonMark/GFM:** headings, paragraphs, emphasis, strong, links,
   images, inline code, fenced code blocks, block quotes, thematic breaks,
   ordered/unordered lists, **tables with alignment**, **task lists**
   (checkboxes), **strikethrough**, raw HTML passthrough.
2. **Local images:** relative *and* absolute POSIX paths are embedded as
   **base64 data URIs** at render time (≤ 25 MB each, no `..` traversal for
   relative). Verified by probe: `loadHTMLString` pages cannot fetch local
   files, so embedding is mandatory.
3. **Mermaid diagrams:** ` ```mermaid ` fences render flowcharts, sequence,
   class, state, ER, pie, gantt… (mermaid.min.js inlined; theme follows
   light/dark; `securityLevel: strict`). Errors surface as styled messages.
4. **KaTeX maths:** inline `$…$` / `\(…\)`, display `$$…$$` / `\[…\]`,
   fenced ` ```math `; fonts embedded as data URIs; offline.
5. **Code highlighting:** highlight.js on fenced blocks (skips mermaid/math);
   GitHub-like light/dark palettes.
6. **Footnotes (GFM style):** line-based pre-pass — `[^key]` refs become
   numbered superscript links; definitions move to a styled footnotes block
   with backlinks. Fenced/indented blocks skipped.
7. **Bare URL autolinking:** `https://…`, `www.…` in prose become links.
8. **Emoji shortcodes:** ~250 curated (`:rocket:` → 🚀).
9. **Callouts (Obsidian):** `> [!note|tip|warning|danger|info|…] Title`
   block quotes become styled callout boxes.
10. **Wikilinks & embeds (Obsidian):** `[[note]]` / `[[note|alias]]` resolve
    against the document folder + all root folders (`.md` implied);
    rendered as dotted links; **clicking opens the target file inside
    MotStar** (JS → `WKScriptMessageHandler` bridge). Unresolved = red.
    `![[image.png]]` embeds inline. Also honoured in print/PDF export.
11. **Tags:** `#topic` / `#folder/tag` styled in prose (skips code/links).
12. **Definition lists:** `Term` / `: definition` → `<dl>` (heuristic
    pre-pass outside fences).
13. **Print CSS:** `@page A4 12mm`, black-on-white cleanup — the same page
    feeds Print and Export-as-PDF so diagrams/maths/images appear there too.

### Editor (Markdown & text)
- Native `NSTextView` source editor: monospaced 13 pt, undo/redo, find bar,
  word wrap on by default (⌥⌘W toggles), smart quotes/dashes off.
- **Create:** ⌘N New Markdown File, ⇧⌘N New Text File (save panel anywhere;
  folder auto-added as root; file revealed/expanded in tree and opened for
  editing).
- **Save:** ⌘S or toolbar; **dirty tracking** against the loaded snapshot;
  switching files prompts **Save / Discard / Cancel**.
- **Discard / Revert:** ⌥⌘R or the toolbar **Revert** button abandons unsaved
  edits by re-reading the file from disk (confirmation only when dirty; the
  editor's undo history is cleared so ⌘Z can't bring the draft back). While
  the preview is showing an unsaved draft, a banner offers **Save** /
  **Discard…** directly. If the file can't be re-read the draft is kept.
- **Edit/Preview toggle** (⌘E) — preview reflects the unsaved draft;
  leaving the editor with unsaved changes prompts **Save / Discard / Cancel**
  (Discard reverts to the on-disk text).
- **Markdown format tools:** format bar above editor (H1 H2 H3, Bold,
  Italic, Code, Quote, List, Numbered, Link, Image) and **Format menu**
  (⌥⌘1/2/3 headings, ⌘B, ⌘I, ⇧⌘K link). Wraps the selection or inserts
  placeholders with the caret inside.
- **Image & file insertion with picker:** Image/Link open a searchable
  `NSOpenPanel`; insert `![alt](path)` / `[text](path)` with the path
  **relative to the document folder** when inside it (absolute otherwise;
  renderer embeds either).

## 6. File actions

- **Print (⌘P):** standard macOS print dialog; per-type strategy same as
  PDF export (below).
- **Export as PDF (⇧⌘E):** save panel → paginated PDF.
  - Markdown: rendered HTML page (full feature set incl. Mermaid/maths).
  - Text: plain monospaced A4.
  - PDF: byte-for-byte copy.
  - Images: full-resolution single page.
  - Office/other: Quick Look snapshot page (best effort).
- **Email (⇧⌘M):** composes a new **Microsoft Outlook** message with the
  file attached via `/usr/bin/osascript` (Apple events). Requires macOS
  Automation permission — the app guides to System Settings and offers
  retry; graceful compose-email fallback only on non-permission errors.
- **Share (⇧⌘S):** Apple share sheet for the file.
- Both disabled while a job is running (busy state) or without selection.

## 7. Quick-find (⌘F)

- Search field at top of sidebar (always visible).
- Debounced (~300 ms) **recursive name search across all roots** (hidden
  files/packages skipped), case/diacritic-insensitive; up to 250 results
  flat list, parent-folder caption; folder results excluded (files only).
- Click result → reveals & selects in tree, clears search.
- Esc clears; while the source editor is open ⌘F belongs to the editor's
  find bar.

## 8. Keyboard shortcuts (full list)

| Shortcut | Action |
|---|---|
| ⌘O | Add Folder… |
| ⌘N / ⇧⌘N | New Markdown File / New Text File |
| ⌘S | Save document |
| ⌥⌘R | Revert to Saved (discard unsaved edits) |
| ⌘E | Toggle Edit / Preview |
| ⌘P / ⇧⌘E | Print / Export as PDF |
| ⇧⌘M / ⇧⌘S | Email (Outlook) / Share |
| ⌘F | Find files in sidebar |
| ⇧⌘R | Markdown Formatted ↔ Raw |
| ⌥⌘F / ⌥⌘W | Focus mode / Word wrap |
| ⌘, | Settings (file sort order) |
| ⌘B / ⌘I | Bold / Italic |
| ⌥⌘1 / 2 / 3 | Heading 1–3 |
| ⇧⌘K | Insert Link |
| (menu) About | App menu → About MotStar |

Menus: File (new/open/save/print/export/email/share), Edit (find),
Format, View (focus/wrap/markdown display), app menu About. Items disabled
when context doesn't apply.

## 9. Behavioural details / lessons learned (important for parity)

- WKWebView `loadHTMLString` **cannot** load local file resources → embed
  images (data URIs) and inline all JS/CSS/fonts.
- `loadFileURL` with a temp HTML outside the granted read-access dir → blank
  page; use `loadHTMLString` instead.
- KaTeX fonts must be inlined (data URIs) to work offline.
- Ad-hoc-signed apps are **auto-denied** by TCC for Apple Events (no prompt,
  no record) — sign with a real certificate **and** route events through
  `/usr/bin/osascript` for correct attribution.
- Newer Outlook (16.112+) creates a message but does **not** open the
  compose window automatically — script must `open` the message.
- NSSharingService must run on the main thread (crashes otherwise).
- Menus + toolbar must share one action layer to keep enablement consistent.
- FSEvents callback needs a C trampoline via `Unmanaged` context pointer.
- Tree expansion state must live outside the view (in state) so
  search/create can reveal programmatically.
- SwiftPM + hand-rolled `.app` bundle: `bundle-app.sh` assembles Info.plist,
  icon (generated via `sips`/`iconutil` from `Resources/appicon-source.jpg`),
  resources and code signature.

## 10. Persistence

- `UserDefaults` key `navstar.rootFolders.v1`: JSON `[{path, addedAt, id}]`.
- Expanded state: session-only (not persisted).
- No other persistent storage. No database. No network. No accounts.

## 11. Build, test, package, release

```sh
swift build            # debug
swift test             # 40 unit tests (registry, markdown, footnotes, wiki, images, PDF export, outlines, editor revert)
./scripts/bundle-app.sh          # release build → build/MotStar.app (Developer ID signed)
./scripts/release.sh             # + DMG/ZIP → notarize → staple → verify
./scripts/release.sh --publish   # …and create/update the GitHub release
./scripts/release.sh --skip-notarize   # local artifacts only
./scripts/notarize.sh <dmg|zip>  # notarize an existing artifact standalone
```

- `scripts/release.sh` is the release pipeline: it fails early without a
  Developer ID identity, notarizes via the `motstar` keychain profile
  (`notarytool store-credentials`), staples the app + container, rebuilds both
  artifacts from the stapled app, and verifies Gatekeeper acceptance
  (`spctl`) of the app inside the DMG and ZIP before optionally publishing.
- `scripts/fetch-phase2-assets.sh` downloads/embeds the web runtimes
  (highlight.js, KaTeX + data-URI fonts, Mermaid).
- Each versioned release hosts `MotStar-<ver>.dmg`, `MotStar-v<ver>-macOS.zip`,
  `allow-dmg.sh` and `install.sh` (one-line installer; asset uploaded as
  `install-motstar.sh` from `scripts/install.sh`).
- Install command:
  `curl -sL https://raw.githubusercontent.com/jbwkode/MotStar/main/scripts/install.sh | bash`
- 40 passing unit tests cover: file-type registry (incl. code-file
  classification), HTML generation (headings/code/tables/links), image
  data-URI embedding (relative + absolute), footnotes,
  wikilinks/definition lists, markdown/text → PDF export, heading-outline
  parsing, code-highlight page generation, and discarding editor edits
  (revert).

## 12. Known limitations / roadmap

- Not notarized (right-click → Open on first launch for others).
- Email requires Automation permission (guided in-app).
- Footnot e pre-pass is line-based (safe inside fences; not for pathological
  nesting); currency `$` can trip inline maths detection.
- No full-text content search yet; no line numbers; no live split
  edit/preview; no wikilink backlinks panel.
- Roadmap: notarized Developer ID distribution → content search → line
  numbers/live split → App Store (sandbox + security-scoped bookmarks).

## 13. Deliverable checklist for a parity build

- [ ] Two-pane window; folder picker; persistence; lazy recursive tree;
      coloured markers + icons; live FSEvents refresh
- [ ] Formatted Markdown with §5 feature list incl. Mermaid, KaTeX,
      highlight.js, footnotes, callouts, wikilinks/embeds, emoji, tags,
      definition lists — fully offline
- [ ] .md/.txt editor: create/save/dirty prompts, Edit-Preview toggle with
      draft rendering, format tools, wrap/focus modes
- [ ] Quick Look (PDF/Office/images), image fit/1:1, raw text
- [ ] Print + Export PDF faithful to preview
- [ ] Outlook email (signed + osascript), Share sheet
- [ ] Quick-find (⌘F) across roots with reveal
- [ ] Full shortcut set + menu integration
- [ ] Unit tests; bundle + DMG + release scripts
