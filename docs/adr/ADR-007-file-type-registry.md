# ADR-007: Central File-Type Registry

**Status:** Accepted

**Context:**
FR-6/FR-7 require colour markers + conventional icons per file type
(.md, text, PDF, DOCX, PPTX, JPG, PNG, XLSX). Colours, icons and preview
strategy must be consistent across the tree and the preview pane and cheap to
change.

**Decision:**
One `FileTypeRegistry` type is the single source of truth. It maps an
extension (case-insensitive) and/or UTI to a `FileKind` enum, and each kind
declares: marker colour, SF Symbol icon name, and preview strategy (text vs
Quick Look). The tree row and the preview pane both consult the registry —
no colour/icon logic anywhere else.

**Consequences:**
- ✅ One-line changes retune the whole UI; spec table (§5.3 of the design
  doc) maps 1:1 to code.
- ✅ Unknown types get a deterministic default (grey `doc`, Quick Look) — the
  accepted Q3 behaviour.
- ⚠️ Extension-based detection can be spoofed (renamed `.txt`→`.docx`);
  acceptable for a navigator; UTI check is the fallback.
- ❌ None material.

**Alternatives considered:**
1. Ad-hoc `switch` on extension spread across views — rejected: drift risk.
2. `NSWorkspace` icons only, no registry — rejected: cannot add colour markers
  or preview strategy in one place.
