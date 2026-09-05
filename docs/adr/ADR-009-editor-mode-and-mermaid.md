# ADR-009: Editor Mode, Documents and Mermaid Rendering

**Status:** Accepted

**Context:**
MotStar must become a working `.md`/`.txt` **editor** (create, edit, save)
as well as a viewer, matching Obsidian-style workflows, and its formatted
preview must handle "all Markdown features" — including Mermaid diagrams
rendered offline. Previews must reflect unsaved drafts.

**Decision:**
- **Document model:** `TextDocument` (in-memory text + loaded snapshot)
  tracks dirty state; one active document per selection; ⌘S writes
  atomically; switching files prompts Save/Discard/Cancel when dirty.
- **Dual mode:** Markdown/text files get a Preview/Edit toggle
  (`FilePaneMode`). Preview renders the **draft** when unsaved
  (text-override path through the HTML renderer), so toggling Edit↔Preview
  shows current work without a reload.
- **Central state:** all editor/print/export/email actions live on the single
  shared `AppState` (menu commands and toolbar call identical code).
- **Tree expansion state** moved into `AppState` (path set) so new files can
  be revealed/expanded programmatically (`revealAndSelect`).
- **Mermaid:** bundled `web/mermaid.min.js` (v10 UMD, offline) is inlined
  into generated Markdown HTML; formatted preview and the PDF/print pipeline
  enable JavaScript for that page so diagrams render. JavaScript remains off
  everywhere else. ADR-008's "JS off" posture is narrowed to: JS on **only**
  for generated Markdown pages, with navigation still locked to the default
  browser and local files embedded as data URIs (never fetched).

**Consequences:**
- ✅ Create/save/edit .md & .txt; dirty tracking; draft-accurate preview,
  print and PDF export.
- ✅ Mermaid flowcharts/sequence/class/etc. render fully offline in preview,
  print and export.
- ⚠️ Enabling JS on Markdown pages means raw `<script>` blocks in user
  documents can execute (renders HTML passthrough); acceptable for the
  user's own local documents; WebKit still sandboxes file access and links
  open externally.
- ⚠️ Mermaid inline runtime adds ~3.3 MB to the app bundle.
- ⚠️ Syntax highlighting, LaTeX (KaTeX), footnotes/autolinks and
  Obsidian-style wikilinks are planned but not yet implemented (Phase 2 of
  docs/03-md-editor-features.md).

**Alternatives considered:**
1. Live split-pane editing (editor + preview simultaneously) — deferred;
   toggle model ships first (documented in the plan).
2. Autosave on typing — deferred; explicit ⌘S + prompts chosen (plan §5.2).
3. Custom scheme handler for local images instead of data-URI embedding —
   rejected earlier (probe showed data URIs are the reliable offline path).
