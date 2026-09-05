# ADR-001: Native SwiftUI App, macOS 14+

**Status:** Accepted

**Context:**
MotStar must be a "native app that runs on Mac OS" with a two-pane UI, tree
navigation, rendered Markdown, Quick Look previews, AppleScript/Outlook email
and Apple share integration. The user is on modern Apple hardware (Apple
Silicon) with Xcode 26.

**Decision:**
Build natively with SwiftUI as the primary UI framework, minimum deployment
target macOS 14 (Sonoma), with deliberate AppKit bridges only where SwiftUI
has no native answer: Quick Look preview (`QLPreviewView`), folder picking
(`NSOpenPanel`), and Outlook automation (`NSAppleScript`). Package layout is a
Swift Package with an executable target so it builds from the command line
and runs from Xcode. No third-party dependencies.

**Consequences:**
- ✅ Small footprint, no runtime dependencies, fast launch, native look & feel.
- ✅ Full access to AppKit bridges needed for Quick Look / Outlook / share.
- ⚠️ SwiftUI list-tree and Markdown capabilities are simpler than a web view
  approach; roadmap items cover richer rendering later (ADR-004).
- ❌ No cross-platform reuse (accepted non-goal).

**Alternatives considered:**
1. Electron/React — rejected: not "native", heavy, contradicts FR-1.
2. AppKit-only — rejected: slower to build tree/preview UI than SwiftUI.
3. macOS 12/13 support — rejected: modern SwiftUI (NavigationSplitView,
   ShareLink) is cleanest on 14+; user hardware supports it.
