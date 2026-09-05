# ADR-002: Root Folder Persistence in UserDefaults (JSON)

**Status:** Accepted

**Context:**
FR-5: MotStar must remember which folders the user chose when it relaunches.
State is small (a handful of folder paths) and owned solely by the app.

**Decision:**
Store the root-folder list as a JSON array of `{ path, addedAt }` objects
under a single `UserDefaults` key (`rootFolders`). On launch, resolve each
path to a URL, verify existence, and mark missing folders with an error state
rather than dropping them silently. Expanded-tree state and the last-selected
file are intentionally not persisted in v1.

**Consequences:**
- ✅ Zero dependencies, trivially debuggable, atomic-ish writes via
  `UserDefaults` synchronization.
- ✅ Same mechanism works sandboxed or not (paths can later be upgraded to
  security-scoped bookmark data — see ADR-003).
- ⚠️ Not appropriate if the list grows large or needs versioned migrations —
  not expected.
- ❌ Expanded state is lost between launches (documented roadmap item).

**Alternatives considered:**
1. SQLite/Core Data — rejected: overkill for one small array.
2. Property list file in Application Support — reasonable, but UserDefaults
   is simpler and adequate for v1.
3. Security-scoped bookmarks from day one — deferred with ADR-003 (sandbox
   is off), schema leaves room to add bookmark data.
