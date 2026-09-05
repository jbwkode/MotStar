# MotStar

Native macOS two-pane document navigator & previewer.

- **Left pane:** recursive, lazily-loaded folder tree. Add any folders from
  storage; they are remembered between launches.
- **Right pane:** previews the selected file — Markdown is rendered neatly
  (formatted **or** raw source via a toolbar toggle), text is plain,
  PDF/Office/images use Quick Look.
- **Toolbar:** **Share** (Apple share sheet), **Email** (composes an
  Outlook message with the file attached), **Print** (standard macOS print
  dialog) and **Export PDF** (save-as-PDF).
- **About:** MotStar menu → About MotStar shows the app logo, version and
  credits.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (for running from source) — built & tested with Xcode 26
- Microsoft Outlook for Mac is optional: Email uses Outlook when installed
  and otherwise falls back to the system compose-email sheet

Dependencies are resolved automatically by SwiftPM on first build
(swift-markdown — Apple's Markdown parser; used for formatted `.md`
rendering).

## Build & Run

### Quick start (terminal)

```sh
swift run MotStar
```

### As a proper .app bundle (recommended)

```sh
./scripts/bundle-app.sh
open build/MotStar.app
```

The script builds a release binary, assembles `build/MotStar.app` with an
Info.plist, and ad-hoc signs it.

### From Xcode

Open `Package.swift` in Xcode, select the **MotStar** scheme (My Mac), and Run.

## Tests

```sh
swift test
```

## First-time Email note

The first Email action prompts macOS: *"MotStar wants to control Microsoft
Outlook."* Grant it in System Settings → Privacy & Security → Automation.
If denied, MotStar falls back to the compose-email sheet.

## Documentation

- `docs/01-product-specification.md` — agreed product specification
- `docs/02-software-design.md` — architecture, C4, data model, security
- `docs/adr/ADR-001…007` — architecture decision records

## Layout

```
Sources/MotStar/
  MotStarApp.swift          app entry
  Models/                   AppState, RootFolder, TreeNode, FileKind (registry)
  Services/                 PersistenceService, FolderEnumerator, EmailService,
                            MarkdownHTML (swift-markdown → styled HTML)
  Views/                    ContentView, SidebarView (tree), PreviewPane,
                            MarkdownViews (Formatted/Raw .md), QuickLookView
Tests/MotStarTests/         unit tests (registry, Markdown rendering)
scripts/bundle-app.sh       .app bundling script
```

## v1 status

Implemented: two-pane UI, folder picker + persistence, recursive lazy tree
with colour markers and standard icons, neat formatted Markdown preview with
Formatted/Raw toggle, plain-text preview, Quick Look for all other types,
Share (Apple sheet), Email via Outlook with fallback, Print, Export as PDF,
About window, app icon + logo, missing-folder error states, unit tests.

Roadmap (see design doc §10): sandbox + bookmarks for App Store, FSEvents
live updates, expanded-state persistence.
