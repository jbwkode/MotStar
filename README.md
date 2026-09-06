# MotStar

**MotStar** is a native macOS document navigator, Markdown editor and
previewer. Browse your folders in a two-pane window, open any file in place —
Markdown, text, source code, PDF, Office documents, images — and edit
`.md`/`.txt` files with full formatted previews.

**Author:** John B. Walsh — [john.b.walsh@gmail.com](mailto:john.b.walsh@gmail.com)

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue) ![License: MIT](https://img.shields.io/badge/license-MIT-green.svg) ![Swift](https://img.shields.io/badge/Swift-5.10-orange)

## Features

- **Two-pane file browser** — recursive, lazily loaded folder tree; folder
  list is remembered between launches; live refresh when files change on disk;
  configurable file ordering (newest-first or A–Z) in Settings (⌘,)
- **Markdown preview** — tables, task lists, strikethrough, footnotes, code
  highlighting, **Mermaid diagrams**, **KaTeX maths**, emoji shortcodes,
  Obsidian-style **callouts**, **wikilinks** (`[[note]]`) and **embeds**
  (`![[image.png]]`) — all rendered **offline**, no network required
- **Built-in editor** — create, edit and save `.md`/`.txt`; Edit/Preview
  toggle, dirty-state tracking, markdown format tools, focus mode
- **Syntax-highlighted code viewer** — source files open as readable,
  colour-coded documents (Swift, Python, JS/TS, C/C++, Go, Rust, shell, …)
  with the language auto-detected
- **Document outline** — headings of the current note in a side pane; click
  to jump the editor or preview to that section
- **Sidebar file operations** — rename, move to folder, move to trash, reveal
  in Finder (right-click or File menu)
- **Quick Look** for PDF, Office (Word/Excel/PowerPoint) and image files —
  large images auto-scale to fit
- **Print & Export as PDF** from any file type
- **Share** via the Apple share sheet; **Email** the selected file through
  Microsoft Outlook
- **Quick-find** (⌘F) across all your folders
- 100% local: no accounts, no cloud, no telemetry

## Install (from the Release)

1. Go to the **Releases** page and download **`MotStar-0.3.6.dmg`**
   (a `.zip` of the app is also available).
2. Open the DMG and drag **MotStar.app** onto the **Applications** shortcut
   inside the window (or drag it into your Applications folder manually).
3. **First launch:** the app is signed with an Apple Development identity but
   is **not yet notarized**, so macOS may block it. If you see
   *"MotStar can't be opened"*, right-click (or Ctrl-click) **MotStar.app** →
   **Open** → **Open** again. You only need to do this once.
4. Launch MotStar, click **Add Folder…** and pick the folders you want to
   browse.

### Automated install (script)

Download and run **`install-motstar.sh`** from the release, or paste:

```bash
curl -sL https://raw.githubusercontent.com/jbwkode/MotStar/main/scripts/install.sh | bash
```

The script fetches the latest DMG, installs to /Applications (backing up any
existing copy), clears the quarantine flag and launches MotStar.
Pin a specific release with `VERSION=v0.3.6`. Anonymous downloads work with no
setup — no token, no account.

### Manual install from a DMG (helper)

Prefer dragging the app yourself? **`allow-dmg.sh`** clears the quarantine
attributes on the DMG and the app inside it, then opens the volume in Finder
so you can drag **MotStar.app** into /Applications without Gatekeeper
interference:

```bash
bash allow-dmg.sh ~/Downloads/MotStar-0.3.6.dmg   # or no args = newest in ~/Downloads
```

> Requires **macOS 14 (Sonoma) or later**. Apple Silicon or Intel.
> Notarized distribution is planned for a future release.

### Email via Outlook (optional)

The first time you use **Email**, macOS asks whether MotStar may control
Microsoft Outlook — click **OK** in the system prompt, then Outlook opens a
new message with the file attached. If permission was missed, the app guides
you to *System Settings → Privacy & Security → Automation*.

## Build from source

Requires Xcode (macOS 14+ SDK).

```sh
# Run directly from the terminal
swift run MotStar

# Or build a proper .app bundle (signs with your Apple Development identity
# if one is installed, otherwise ad-hoc)
./scripts/bundle-app.sh
open build/MotStar.app
```

Or open `Package.swift` in Xcode, select the **MotStar** scheme, and Run.

### Tests

```sh
swift test
```

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘O / ⌘N / ⇧⌘N | Add folder / New Markdown file / New text file |
| ⌘S / ⌘E | Save / Toggle Edit-Preview |
| ⌘P / ⇧⌘E | Print / Export as PDF |
| ⇧⌘M / ⇧⌘S | Email / Share |
| ⌘F | Find files in sidebar |
| ⇧⌘R | Markdown: formatted ↔ raw |
| ⌥⌘O | Show / hide the document outline |
| ⌘R / ⌘⌫ | Rename selection / Move selection to Trash |
| ⌘+ / ⌘− / ⌘0 | Zoom in / out / actual size (reader & editor) |
| ⌥⌘F / ⌥⌘W | Focus mode / Word wrap |
| ⌘, | Settings (theme, text size, file sort order, …) |
| ⌘B ⌘I ⌥⌘1-3 ⇧⌘K | Bold / Italic / Headings / Link |

## Documentation

- [`docs/01-product-specification.md`](docs/01-product-specification.md) —
  agreed product specification
- [`docs/02-software-design.md`](docs/02-software-design.md) — architecture,
  C4 diagrams, data model
- [`docs/03-md-editor-features.md`](docs/03-md-editor-features.md) — Markdown
  editor feature inventory & roadmap
- [`docs/adr/`](docs/adr/) — architecture decision records (ADR-001…009)
- [`Examples/`](Examples/) — sample documents exercising every renderer
  feature

## License

MotStar is open source, released under the [MIT License](LICENSE).

Copyright (c) 2026 John B. Walsh — [john.b.walsh@gmail.com](mailto:john.b.walsh@gmail.com)

You are free to use, modify, and distribute the code, provided the copyright
and permission notice are preserved. The app itself is distributed as signed
release builds; see the [releases](https://github.com/jbwkode/MotStar/releases)
page.

## Roadmap

- Notarized Developer ID distribution
- Full-text content search
- Line numbers & live split edit/preview
- App Store distribution (sandbox + security-scoped bookmarks)
