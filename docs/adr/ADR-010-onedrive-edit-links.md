# ADR-010: OneDrive edit links via Microsoft Graph

**Status:** Accepted

**Context:**
Files selected in MotStar often live in a OneDrive or SharePoint sync folder.
Emailing them as attachments duplicates content and loses the live document.
The desired behaviour is a "quick share": for a cloud-backed file, email a
**link that grants edit access** instead of (or as well as) the attachment.

Two hard constraints:
1. The local path alone is not a shareable URL; the link must be minted in the
   cloud.
2. OneDrive for Mac exposes **no** programmatic share API to other apps — its
   Finder integration is a FinderSync context menu, and it registers no
   `NSSharingService` (probed: AirDrop/Messages/Notes/… only). So a
   "open the OneDrive share dialog" hand-off is not possible without UI
   automation.

**Decision:**
Add a Microsoft Graph client (`OneDriveShareService`):
- **Detection:** a file under `/Library/CloudStorage/OneDrive*` or
  `/Library/CloudStorage/SharePoint*` (and the legacy `~/OneDrive` layout) is
  treated as cloud-backed.
- **Auth:** OAuth 2.0 **device code** flow (no redirect URI/browser embedding),
  delegated scope `Files.ReadWrite offline_access`; tokens in the Keychain.
  Requires an Entra ID app registration (public client, delegated Graph
  permission). The Application (client) ID / tenant are configured in
  Settings → OneDrive sharing; no credentials ship in the app.
- **Link:** `GET /me/drive/root:/{path}` to resolve the item, then
  `POST /me/drive/items/{id}/createLink` with `{type: "edit",
  scope: "organization"}`.
- **Email:** the link is placed in the Outlook message body (no attachment).
  Any failure (not signed in, not cloud-backed, tenant blocks sharing, network)
  falls back to the existing attach behaviour.

**Consequences:**
- ✅ Real one-click edit link for the user's own OneDrive/SharePoint files.
- ✅ No credentials in the app; least-privilege delegated scope; Keychain.
- ⚠️ Adds **network I/O** and an external identity flow. This revises ADR-003
  (no-sandbox justification) and the spec's "fully local, no network" claim;
  the feature is opt-in (no client ID → feature off).
- ⚠️ Resolves against the **signed-in user's default drive** only. Files synced
  from a *different* account (e.g. `OneDrive-Personal(2)` when signed in to
  another) or a SharePoint library outside `/me/drive` need drive selection and
  are not supported in this version.
- ⚠️ `scope: organization` may be blocked by tenant policy; anonymous links are
  deliberately not used (data-leak risk, especially clinical content).
- ⚠️ Sign-in consent may require admin approval; the device-code UX is clunkier
  than an embedded browser.

**Alternatives considered:**
1. Finder hand-off (reveal file → user uses OneDrive → Copy link → MotStar reads
   the clipboard) — rejected: cannot open OneDrive's share UI programmatically,
   and it is 2+ manual steps.
2. Anonymous `createLink` — rejected: security/compliance risk.
3. Path→URL heuristics — rejected: unreliable across accounts/libraries and the
   link still needs a sharing grant.
4. MSAL with embedded web auth — deferred: more dependencies and redirect-URI
   setup; device code keeps the app dependency-free.
