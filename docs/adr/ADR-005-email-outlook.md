# ADR-005: Email via Microsoft Outlook (AppleScript) with Fallback

**Status:** Accepted

**Context:**
FR-11: the Email button must email the selected file "via Outlook". Outlook
for Mac supports scripting attachments through its AppleScript dictionary.
A user action must always have a sane outcome.

**Decision:**
`EmailService` runs a small AppleScript (`NSAppleScript`) that asks Microsoft
Outlook to create a **new outgoing message with the file attached** and
activate it — the user addresses and sends; MotStar never auto-sends.
Resolution order:
1. If Microsoft Outlook is installed → run the script.
2. If the script fails (Outlook not installed / automation denied / error) →
   fall back to the macOS compose-email share service with the file attached.
3. Any failure surfaces an alert explaining the exact next step (e.g., grant
   automation permission in System Settings > Privacy & Security).

**Consequences:**
- ✅ Meets "via Outlook" exactly while keeping a graceful path otherwise.
- ✅ No credentials stored; message reviewed by the user before send.
- ⚠️ First run triggers a TCC automation prompt; denial handled in step 2/3.
- ⚠️ AppleScript automation can break with future Outlook versions — the
  service is isolated behind one protocol so the script is easy to patch.

**Alternatives considered:**
1. `NSSharingService.composeEmail` only — rejected: uses the *default* mail
  app (usually Apple Mail), not Outlook.
2. Outlook `ms-outlook://` URL scheme — rejected: cannot attach files.
3. Auto-sending via script — rejected: unsafe and against spec intent.
