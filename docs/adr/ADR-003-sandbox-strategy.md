# ADR-003: App Sandbox Disabled for v1

**Status:** Accepted

**Context:**
FR-4/FR-5 require reading arbitrary user-chosen folders and remembering them
across launches. The App Sandbox (required for Mac App Store distribution)
would force security-scoped bookmarks and entitlement setup. The primary
distribution path for v1 is Developer-ID signed, installed outside the App
Store.

**Decision:**
Ship v1 without the App Sandbox enabled. Persist root folders by path
(ADR-002). When App Store distribution is pursued, enable the sandbox and
migrate persistence to security-scoped bookmark data (stored base64 next to
each path — a backwards-compatible schema extension).

**Consequences:**
- ✅ Simplest correct behaviour for folder access and relaunch restore.
- ✅ No entitlement/notarization friction during development.
- ⚠️ Lower security posture than sandboxed apps; acceptable for a personal
  productivity tool that performs no network I/O (spec §6).
- ❌ Must revisit for Mac App Store; revisit includes bookmark migration and
  hardened-runtime testing.

**Alternatives considered:**
1. Sandbox + security-scoped bookmarks now — rejected: added complexity
  (access-grant lifecycle, bookmark resolution failures) with no immediate
  distribution benefit.
2. Electron with unrestricted Node fs — rejected by ADR-001 anyway.
