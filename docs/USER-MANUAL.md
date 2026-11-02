# MotStar User Manual

**A native macOS viewer and editor for Markdown, notes and documents.**

MotStar opens a folder, shows it as a tree, and renders whatever you click —
Markdown, plain text, source code, PDFs, Word, Excel and PowerPoint files,
images — without leaving the window. You can create and edit `.md` and `.txt`
files in place.

MotStar is entirely local: no accounts, no cloud, no telemetry. Nothing leaves
your Mac unless you explicitly share, email or export a file.

- **Requires:** macOS 14 (Sonoma) or later, Apple Silicon or Intel
- **Version:** 0.3.13
- **Author:** John B. Walsh — [john.b.walsh@gmail.com](mailto:john.b.walsh@gmail.com)

> Open this manual at any time with **Help → MotStar User Manual** (⌘?).

---

## Contents

1. [Installing](#1-installing)
2. [First run: adding folders](#2-first-run-adding-folders)
3. [The window](#3-the-window)
4. [Reading files](#4-reading-files)
5. [Browsing the folder tree](#5-browsing-the-folder-tree)
6. [Finding files](#6-finding-files)
7. [Creating files](#7-creating-files)
8. [Editing Markdown and text](#8-editing-markdown-and-text)
9. [Pasting images into a note](#9-pasting-images-into-a-note)
10. [Markdown features](#10-markdown-features)
11. [Printing and exporting](#11-printing-and-exporting)
12. [Sharing and email](#12-sharing-and-email)
13. [Managing files](#13-managing-files)
14. [Appearance and text size](#14-appearance-and-text-size)
15. [Keyboard shortcuts](#15-keyboard-shortcuts)
16. [Troubleshooting](#16-troubleshooting)
17. [Support](#17-support)

---

## 1. Installing

Releases are **signed with a Developer ID certificate and notarized by
Apple**, with the ticket stapled to both the app and the disk image. macOS
accepts them on first launch — there is no right-click workaround and no
`xattr` step, even offline.

1. Download **`MotStar-<version>.dmg`** from the
   [Releases page](https://github.com/jbwkode/MotStar/releases).
2. Open the disk image and drag **MotStar.app** onto the **Applications**
   shortcut.
3. Launch it from Applications, Launchpad or Spotlight.

**Or install from the terminal**, which fetches the latest release, backs up
any existing copy and launches the app:

```bash
curl -sL https://raw.githubusercontent.com/jbwkode/MotStar/main/scripts/install.sh | bash
```

Pin a version with `VERSION=v0.3.13 bash install.sh`. To remove MotStar, quit
it and drag **MotStar.app** from Applications to the Trash.

Your settings live in `~/Library/Preferences/com.motstar.mac.plist` and are
removed with the app only if you delete them yourself; deleting the app does
not touch any of your documents.

---

## 2. First run: adding folders

MotStar shows nothing until you give it at least one folder to work in.

1. Click **Add Folder…** in the sidebar, or press **⌘O**.
2. Choose a folder — your notes vault, a project directory, a downloads
   folder, anything.
3. The folder appears as a collapsible row in the sidebar.

Each folder you add is remembered between launches. Add as many as you like:
a second brain folder, a work repo and a scratch directory can sit side by
side. To stop working in a folder, **right-click** its row in the sidebar and
choose **Remove "…"** — this only removes it from MotStar's list, it never
deletes anything from disk.

MotStar ignores hidden files and folders (names starting with `.`) and
tolerates folders that disappear or become unreadable — they show an inline
"Unavailable" state instead of crashing.

---

## 3. The window

Two panes, left to right:

| Pane | What it does |
|---|---|
| **Sidebar** | Your folders as a tree, plus the quick-find box. Resize it by dragging the divider |
| **Preview / editor** | Renders the selected file, or edits it in source mode |

A toolbar above the preview carries the actions that apply to the selected
file: mode toggle (Edit / Preview), **Share**, **Email**, **Print**,
**Export PDF**, **Export HTML**, plus zoom and focus controls. The same
actions are in the menu bar with keyboard shortcuts.

The **title bar** shows the document's name. The left edge of the sidebar can
be collapsed; drag the divider back to restore it.

---

## 4. Reading files

Click any file in the tree and it renders in the right pane.

| File type | How MotStar shows it |
|---|---|
| **Markdown** (`.md`, `.markdown`, `.mdown`) | Fully formatted, offline: headings, tables, lists, code, maths, diagrams, callouts, footnotes, wikilinks and embedded images |
| **Plain text** (`.txt`, logs, configs) | Monospaced text with the same reading controls |
| **Source code** (`.swift`, `.py`, `.js`, `.ts`, `.c`, `.h`, `.go`, `.rs`, `.sh`, `.json`, `.yaml`, `.toml`, `.html`, `.css`, …) | Syntax-highlighted, with the language detected from the extension |
| **PDF** | Rendered in place, page by page |
| **Word** (`.docx`) | Converted to formatted text with headings, lists, tables and working links |
| **Excel** (`.xlsx`) | Sheet contents as a clean table |
| **PowerPoint** (`.pptx`) | Slide-by-slide with titles, lists and inline images |
| **Images** | PNG, JPEG, HEIC, GIF and friends render inline; SVG too |
| **Anything else** | Opened in whichever app macOS associates with the type |

Markdown views can be toggled between **formatted** and **raw source** with
**⇧⌘R** — handy for checking what a renderer is doing.

Reading aids:

- **⌘+ / ⌘− / ⌘0** — zoom the current pane's text, or reset it
- **⌥⌘F** — focus mode: hide the sidebar and centre the reading column
- **⌥⌘O** — show the document outline for Markdown, click a heading to jump

---

## 5. Browsing the folder tree

- **Click a disclosure triangle** to expand a folder. Contents load lazily as
  you open them, so huge folders stay fast.
- Folders always sort alphabetically, first. Files within a folder sort by
  **Newest first** or **Alphabetical (A–Z)** — set in **Settings → File tree**.
- **File icons are colour-coded** by type: Markdown, text, code, PDF, Word,
  Excel, PowerPoint and images each have their own marker colour, so you can
  scan a folder at a glance.
- The tree refreshes itself when files change on disk, so edits made in another
  app appear without a manual reload.

---

## 6. Finding files

Press **⌘F** (or click the search box at the top of the sidebar) and type.

- Results are files whose **name** matches, across **all** your folders, with
  the containing folder shown underneath each hit.
- **↑ / ↓** move through results, **Return** opens one, **Esc** clears the
  search and returns to the tree.

While the source editor is open, **⌘F** belongs to the editor's own find bar
instead. Click into the sidebar search box to search files again.

---

## 7. Creating files

**File → New Markdown File…** (**⌘N**) or **New Text File…** (**⇧⌘N**).

The save panel opens **in the folder you were last working in** — the folder of
the file you selected, a folder you expanded in the sidebar, or a folder you
just added. That location is remembered between launches. If it no longer
exists, MotStar falls back to the open document's folder, then your first
folder.

Name the file and save:

- New Markdown files start with a `# New Document` heading and the cursor ready
  to type.
- The file appears in the tree, selected, and MotStar switches you straight
  into the editor.
- If the location isn't inside one of your folders, MotStar adds its folder so
  the file is visible in the sidebar.

---

## 8. Editing Markdown and text

Select a `.md` or `.txt` file and press **⌘E**, or use the **Edit / Preview**
control in the toolbar. The right pane becomes a source editor.

| Action | Shortcut |
|---|---|
| Toggle Edit / Preview | **⌘E** |
| Save | **⌘S** |
| Revert to the version on disk | **⌥⌘R** |
| Toggle word wrap | **⌥⌘W** |
| Toggle focus mode | **⌥⌘F** |
| Bold / Italic / Inline code | **⌘B** / **⌘I** / no default |
| Link | **⇧⌘K** |
| Heading 1–3 | **⌥⌘1** … **⌥⌘3** |
| Blockquote, bullet list, numbered list | **Format** menu |
| Paste image from clipboard | **⇧⌘V** |

Notes:

- MotStar tracks whether a file has **unsaved changes** and asks before you
  navigate away or close it. There is at most one editor open at a time.
- **Revert to Saved** (⌥⌘R) discards your edits and reloads from disk, after
  a confirmation. This cannot be undone.
- Preview shows a banner while it is displaying unsaved edits, with **Save**
  and **Discard…** buttons.
- Files opened from inside the app bundle — such as this manual — are
  read-only; the Edit control stays disabled.

---

## 9. Pasting images into a note

The fastest way to get a screenshot into a note:

1. Copy an image — ⇧⌃⌘4 to capture a region, or use Preview, or any app's
   Copy.
2. Put the cursor where the image belongs in the **source editor**.
3. Press **⇧⌘V**, or use **Format → Paste Image from Clipboard**, or
   right-click → **Paste**.

MotStar:

- writes the image next to your note in an **`images/`** folder, creating it
  if needed;
- names it **`image-<timestamp>.png`**, adding a suffix rather than ever
  overwriting an existing file;
- normalises TIFF and other clipboard formats to **PNG**;
- inserts the **relative link** at the cursor, e.g.
  `![](images/image-2026-10-30-125730.png)`.

Relative links mean the note and its images stay together if you move or sync
the folder. The preview renders them offline, with no network access.

---

## 10. Markdown features

MotStar uses a CommonMark core plus GitHub-flavoured extensions:

- **Headings, bold, italic, strikethrough, inline code**
- **Tables** with alignment
- **Task lists** (`- [ ]` / `- [x]`)
- **Fenced code blocks** with syntax highlighting
- **Footnotes** (`[^1]`)
- **Maths** via KaTeX — inline `$…$` and display `$$…$$`
- **Mermaid diagrams** in ` ```mermaid ` blocks
- **Callouts / admonitions**
- **Wikilinks and embeds** — `[[note]]` and `![[image.png]]`, resolved across
  your added folders
- **Images** — relative paths, absolute paths, and pasted images
- **Front matter** at the top of a file
- **Definition lists**

Everything renders **offline**: highlight.js, KaTeX, fonts and Mermaid are
bundled inside the app.

---

## 11. Printing and exporting

| Action | Shortcut | Result |
|---|---|---|
| **Print Selected File…** | **⌘P** | Prints the rendered document, paginated to A4 |
| **Export Selected File as PDF…** | **⇧⌘E** | Writes a paginated, selectable-text PDF |
| **Export Selected File as HTML…** | **⇧⌘H** | Writes a self-contained HTML file — styles, fonts and images inlined |

Word, code and plain-text files export as properly paginated documents rather
than one endless page. Export honours unsaved editor changes, so you can
export a draft without saving it first.

---

## 12. Sharing and email

- **Share** (**⇧⌘S**) opens the macOS share sheet for the selected file —
  AirDrop, Messages, Mail, Notes and anything else you have installed.
- **Email** (**⇧⌘M**) composes a new message in **Microsoft Outlook** with the
  file attached.

The first time you use Email, macOS asks whether MotStar may control Outlook —
click **OK**. If you dismissed that prompt, enable it later in
**System Settings → Privacy & Security → Automation → MotStar → Microsoft
Outlook**.

---

## 13. Managing files

From the **File** menu or a file's **right-click** menu:

| Action | Shortcut | Notes |
|---|---|---|
| **Rename…** | **⌘R** | The extension is preserved; refuses to overwrite an existing name |
| **Move to Folder…** | — | Picks a destination folder |
| **Move to Trash** | **⌘⌫** | Asks first; recoverable from the Trash |
| **Reveal in Finder** | — | Shows the file in its folder |

Folder rows can be renamed, moved and trashed the same way, and the whole
subtree moves with them. Root folders can only be removed from MotStar's list,
never renamed or trashed, because they're workspace containers rather than
contents.

Unsaved editor changes are handled before any destructive action: MotStar asks
whether to **Save**, **Discard** or **Cancel**.

---

## 14. Appearance and text size

**MotStar → Settings…** (**⌘,**):

- **Theme** — System, Light or Dark. Applies to the whole app, preview
  included.
- **Text size** — separate sizes for **Reading** (formatted preview) and
  **Editor** (source), 9–30 pt. The same values can be nudged live with
  ⌘+ / ⌘− / ⌘0 in any pane.
- **File tree** — sort files **Newest first** or **Alphabetical (A–Z)**.
  Folders are always alphabetical.

Reading preferences persist across launches.

---

## 15. Keyboard shortcuts

### Files

| Shortcut | Action |
|---|---|
| ⌘N | New Markdown file |
| ⇧⌘N | New text file |
| ⌘O | Add folder |
| ⌘S | Save |
| ⌥⌘R | Revert to saved |
| ⌘R | Rename selected file |
| ⌘⌫ | Move selected file to Trash |

### View and reading

| Shortcut | Action |
|---|---|
| ⌘E | Toggle Edit / Preview |
| ⇧⌘R | Toggle formatted / raw Markdown |
| ⌥⌘O | Show document outline |
| ⌥⌘F | Focus mode |
| ⌥⌘W | Toggle word wrap |
| ⌘+ / ⌘− / ⌘0 | Zoom in / out / reset |
| ⌘F | Quick-find files in the sidebar |

### Output

| Shortcut | Action |
|---|---|
| ⌘P | Print |
| ⇧⌘E | Export as PDF |
| ⇧⌘H | Export as HTML |
| ⇧⌘S | Share |
| ⇧⌘M | Email via Outlook |

### Editing

| Shortcut | Action |
|---|---|
| ⌘B / ⌘I | Bold / Italic |
| ⇧⌘K | Insert link |
| ⌥⌘1 … ⌥⌘3 | Heading 1–3 |
| ⇧⌘V | Paste image from clipboard |

### App

| Shortcut | Action |
|---|---|
| ⌘, | Settings |
| ⌘? | This manual |

---

## 16. Troubleshooting

**"MotStar is damaged" or macOS refuses to open it**
That should not happen with 0.3.11 or later, which are notarized and stapled.
Confirm what you have:

```bash
spctl --assess --type execute -vv /Applications/MotStar.app
```

Expect `source=Notarized Developer ID`. If it says otherwise, the download was
damaged or modified — delete it and download again from the Releases page.

**A folder shows "Unavailable"**
MotStar can't read it: it was moved, deleted, or you lack permission. Use
**System Settings → Privacy & Security → Files and Folders** to grant access,
or remove the folder from the sidebar and add it again.

**⌘F doesn't search files**
While the source editor is open, ⌘F is the editor's find bar. Click the
sidebar search box, or leave the editor, then press ⌘F.

**Email does nothing**
Outlook isn't installed, or the Automation permission was denied. Install
Outlook, then enable it in **System Settings → Privacy & Security →
Automation**.

**PDF or Office preview looks empty**
Some documents rely on fonts or structures that can't be rendered inline.
Use **Reveal in Finder** and open them in their native app; MotStar will still
print and export Markdown/text files.

**Images don't appear in a note**
Check the link is relative to the note's own folder and that the file exists.
Pasted images always go to `images/` beside the note; hand-written links must
point somewhere that exists.

**Edits were lost**
MotStar asks before discarding unsaved changes, and **Revert to Saved**
requires confirmation. If a file is modified by another app while you have
unsaved edits, MotStar keeps your draft rather than silently reloading.

---

## 17. Support

MotStar is developed and maintained by John B. Walsh.

- **Email:** [john.b.walsh@gmail.com](mailto:john.b.walsh@gmail.com)
- **Issues and feature requests:**
  [github.com/jbwkode/MotStar/issues](https://github.com/jbwkode/MotStar/issues)
- **Releases:**
  [github.com/jbwkode/MotStar/releases](https://github.com/jbwkode/MotStar/releases)

Provided as-is, on a best-effort basis, with no SLA or paid support. Keep
backups of anything you care about — MotStar only ever changes files when you
explicitly create, edit, save, rename, move or trash them.
