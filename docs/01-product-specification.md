# MotStar — Product Specification

**Version:** 0.1 (draft for review)
**Date:** 2026-09-05
**Platform:** macOS (native Mac app)
**Status:** Open questions marked **[?]** — see Section 9

---

## 1. Overview

MotStar is a native macOS document navigation and preview application. The
user registers folders of their choosing, browses a full recursive file/folder
tree, and previews file contents — all in a single two-pane window. It is a
local, offline tool: no accounts, no cloud sync, no server.

## 2. Goals & Non-Goals

### Goals
- Fast, native navigation of locally stored folders.
- Remember the user's chosen folders between launches.
- Clearly identify supported file types via colour-coded markers and standard
  icons.
- Preview file contents in-place (Markdown rendered properly).
- Send the selected file via Outlook email or the macOS share sheet with one
  click.

### Non-Goals
- Editing files (read-only preview only).
- Searching or indexing file contents (out of scope for v1).
- Cloud storage / remote file systems.
- Cross-platform support (macOS only).

## 3. Functional Requirements

### FR-1 Native macOS application
The app is a native macOS application (Swift/SwiftUI), distributed as a
standard `.app` bundle. **[?]** Minimum supported macOS version — see Q1.

### FR-2 Two-pane main screen
The main window is split into two panes:
- **Left pane:** folder tree (navigation).
- **Right pane:** preview of the selected file.
The divider is user-resizable; pane widths persist between launches.

### FR-3 Left pane — root folders list
The left pane shows a list of root folders the user has chosen. The user can
expand any folder to a full **recursive tree** of sub-folders and files and
navigate up and down the tree freely (collapse/expand nodes).

### FR-4 Adding folders
The user adds folders from local storage via a folder picker (macOS
"Open…" panel). Added folders appear as new roots in the left pane.
- Multiple folders may be added.
- Duplicate additions are ignored (folder already present).
- Folders can be removed from the list (without deleting from disk).

### FR-5 Persistence across launches
The set of chosen root folders (and, where practical, the expanded state of
the tree) is restored automatically when the app is relaunched.

### FR-6 File type identification
When the user clicks a folder and its contents are listed, **every supported
file** is shown with a **coloured marker** beside its file name that signifies
its type. Supported types and their default markers are defined in the
registry (Section 5). **[?]** Handling of unsupported file types — see Q3.

### FR-7 Standard icons
Each file/folder row uses the conventional macOS icon for its type
(NSImage/SF Symbols / `NSWorkspace.icon(forFile:)`), in addition to the
colour marker of FR-6. Folders use the standard folder icon.

### FR-8 Selection & preview
Clicking a file in the left pane shows its contents in the right pane.
Clicking a folder row navigates/toggles the tree rather than previewing.

### FR-9 Markdown rendering
`.md` files are rendered as **formatted Markdown** in the preview pane
(headings, lists, code blocks, block quotes, tables, links, images — styled
with a clean typeface and light/dark support), not shown as raw text.
A **Formatted / Raw** toggle button at the top of the preview pane switches
between the formatted view and the raw Markdown source (monospaced,
selectable). The default view is Formatted.

### FR-10 Preview of other supported types
`.txt` is shown as plain text; PDF, DOCX, PPTX, XLSX, JPG and PNG are shown
via the standard macOS preview mechanism (Quick Look) in the right pane.
**[?]** Confirm Quick Look is acceptable for Office/PDF/image types — see Q4.

### FR-11 Email button (Outlook)
A toolbar button above the preview pane composes an email to the selected file
**via Microsoft Outlook**: it opens a new Outlook message with the file
already attached, ready for the user to address and send. **[?]** Behaviour
when Outlook is not installed — see Q2.

### FR-12 Share button (Apple share sheet)
A toolbar button beside Email opens the standard macOS share sheet
(`NSSharingServicePicker`) for the selected file, exposing Apple's built-in
share destinations (AirDrop, Messages, Mail, Notes, etc.) per Apple's share
definitions.

### FR-13 Print
A **Print** toolbar button prints the selected file through the standard
macOS print dialog (paper size/margins follow the document CSS). Markdown and
text print as paginated, formatted documents; PDFs print directly; images and
Office/other types print from their Quick Look representation.

### FR-14 Export as PDF
An **Export PDF** toolbar button saves the selected file as a PDF via the
standard save panel: Markdown/text are rendered to a paginated A4 PDF with
the formatted styling; PDFs are saved as a copy; images are wrapped at full
resolution; Office/other types export a Quick Look snapshot page.

### FR-15 About window
The app menu (MotStar → About MotStar) opens an About window showing the
logo, app name, version, platform, and credits.

## 4. UI Sketch (textual)

```
┌──────────────────────────────────────┬────────────────────────────────────┐
│ Left pane                            │ Right pane (preview)               │
│                                      │                                    │
│  ➤ Projects            (folder)      │  ┌──────────────────────────────┐  │
│    ➤ Reports                        │  │  [Share] [Email]   ← toolbar │  │
│      📄 Q3.md        ● (indigo)      │  ├──────────────────────────────┤  │
│      📄 Notes.txt    ● (grey)        │  │                              │  │
│      📄 Brief.pdf    ● (red)         │  │   Rendered Markdown /        │  │
│      ➤ Data                         │  │   text / Quick Look preview   │  │
│    ➤ Assets                         │  │                              │  │
│  ➤ Archive             (folder)      │  │                              │  │
│  ＋ Add Folder…                      │  │                              │  │
└──────────────────────────────────────┴────────────────────────────────────┘
```

**Toolbar (right pane, top):**
- **Share** — Apple share sheet for the selected file (FR-12).
- **Email** — Outlook message with the selected file attached (FR-11).
- **Formatted | Raw** — display mode toggle, shown only for `.md` files
  (FR-9).
- Buttons are disabled when nothing is selected.

## 5. File Type Registry

The colour marker and icon per type. Defaults below are proposed; colours and
icons are configurable in one place in code.

| Type            | Extensions             | Marker colour            | Conventional icon (SF Symbol) |
|-----------------|------------------------|--------------------------|-------------------------------|
| Markdown        | `.md`                  | Indigo `#6366F1`         | `doc.richtext`               |
| Plain text      | `.txt`                 | Grey `#9CA3AF`           | `doc.plaintext`              |
| PDF             | `.pdf`                 | Red `#E53E3E`            | `doc.richtext` (red accent)  |
| Word document   | `.docx`                | Word blue `#2B579A`      | `doc.text`                   |
| PowerPoint      | `.pptx`                | PowerPoint orange `#D24726` | `chart.bar.doc.horizontal` |
| Excel workbook  | `.xlsx`                | Excel green `#217346`    | `tablecells`                 |
| JPEG image      | `.jpg`, `.jpeg`        | Cyan `#06B6D4`           | `photo`                      |
| PNG image       | `.png`                 | Cyan `#06B6D4`           | `photo`                      |

Notes:
- The "coloured item beside each file name" (FR-6) is a small colour badge/dot
  rendered at the leading edge of the row.
- `.md` and `.txt` detection is case-insensitive; Office/PDF/image detection
  may additionally use UTI (`UTType`) for robustness.
- **[?]** Should JPG and PNG use one shared image colour or distinct colours?

## 6. Non-Functional Requirements

- **Performance:** tree expansion is lazy (only requested directory levels
  are read); large folders (10k+ entries) must not freeze the UI.
- **Reliability:** a folder that becomes unavailable (drive disconnected) must
  not crash the app — show it greyed with an error state.
- **Privacy:** fully local. No telemetry, no network calls, no document
  content leaves the machine (except when the user explicitly emails/shares).
- **Accessibility:** keyboard navigation of the tree; VoiceOver labels on
  markers.

## 7. Out of Scope (v1)

- File editing, rename, delete, move.
- Full-text search / tags / favourites.
- Cloud folders (OneDrive/Drive native connectors) — though any local folder
  mounted on disk works.
- Windows/Linux versions.

## 8. Assumptions (to be validated)

1. The user runs macOS with a recent SwiftUI runtime.
2. Microsoft Outlook for Mac is installed for FR-11 (otherwise a defined
   fallback is needed — see Q2).
3. Preview is strictly read-only.
4. "Add folders" means the folder picker flow is owned by MotStar (the app
   stores its own list), not integration with Finder favourites.

## 9. Open Questions

- **Q1 (macOS minimum):** What is the minimum macOS version to support?
  *Recommendation:* macOS 14 (Sonoma) or later — modern SwiftUI APIs, easy.
- **Q2 (Email fallback):** If Outlook is not installed, what should Email do?
  *Recommendation:* fall back to the Apple share/compose-mail sheet so the
  button always does something useful.
- **Q3 (Unsupported types):** Files outside the registry (e.g. `.zip`, `.mov`)
  — show them with a generic grey marker, or hide them from the tree?
  *Recommendation:* show with generic icon + grey marker and open via Quick
  Look; hiding is confusing.
- **Q4 (Preview mechanism):** For PDF/DOCX/PPTX/XLSX/JPG/PNG, is the built-in
  macOS Quick Look preview acceptable inside the right pane?
  *Recommendation:* yes — it is the native, zero-dependency approach.
- **Q5 (Hidden/system files):** Include dotfiles (`.git`, `.DS_Store`)?
  *Recommendation:* hide them by default, no toggle in v1.
- **Q6 (Deliverable):** After the spec is agreed, do you want (a) a full
  software design document + ADRs only, or (b) the design plus a working
  SwiftUI app scaffold you can build in Xcode? *Recommendation:* (b).
