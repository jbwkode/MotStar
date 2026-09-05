# ADR-006: Lazy Depth-on-Demand Tree, Hidden Files Filtered

**Status:** Accepted

**Context:**
FR-3/FR-6: the left pane shows a full recursive tree the user navigates up
and down. Root folders may be huge (home directories, project caches);
eagerly enumerating everything would stall launch and expansion.

**Decision:**
`TreeNode` stores `children: [TreeNode]?`; `nil` means "not yet loaded". A
folder's children are enumerated only when the user first expands that node,
in a single background pass (so the UI never blocks), sorted folders-first
then files (localizedCaseInsensitive). Hidden files and directories (leading
`.`, e.g. `.git`, `.DS_Store`) are excluded (accepted Q5). Missing/unreadable
folders set an inline error state on the node instead of throwing (NFR). Work
is bounded per user interaction — there is no eager full-tree scan; very
large single folders (10k+ entries) render in one pass on the background
queue, which keeps the UI responsive without chunking complexity in v1.

**Consequences:**
- ✅ Bounded work per interaction; large trees stay responsive.
- ✅ Simple mental model and easy to extend (FSEvents refresh later).
- ⚠️ "Full recursive tree" is visual, not materialized: deep navigation
  requires expansion clicks — matches spec §8 (navigate up and down).
- ❌ Symlink cycles are avoided by not following directory symlinks.

**Alternatives considered:**
1. Precompute whole tree in memory — rejected: unbounded cost, no benefit.
2. `NSOutlineView` with data source — viable AppKit route, but SwiftUI
  `DisclosureGroup` recursion is less code and equally lazy given the
  `children == nil` gate.
3. File System Events live watching in v1 — roadmap only.
