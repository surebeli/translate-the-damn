# Windows: masked API Key + draggable popup — Design (2026-06-20)

Two Windows UI improvements. Amends the main design spec (`2026-06-17-…-design.md` §8 popup, §9
settings). Both are UI items (no conformance vector) — verified by build + a per-platform walkthrough.

## A. API Key field = masked/secure entry  (Windows catch-up)

- **Now:** `SettingsWindow.xaml` `TxtApiKey` is a plain `TextBox` (plaintext key on screen).
- **macOS:** already masks via `SecureField` (`DSSettingsView.swift`) — so this is Windows catching up,
  **not** a new feature; no Law-3 violation is created.
- **Change:** `TxtApiKey` → WPF `PasswordBox`; load `TxtApiKey.Password = bc.ApiKey`, save
  `bc.ApiKey = TxtApiKey.Password`. No reveal toggle in v1 (mirror macOS `SecureField`).
- **Spec:** §9 shared rule — "API Key field is a masked/secure entry; never plaintext."
- **Parity:** `API Key field masked` §9 — (UI): Win ⬜→✅, macOS ✅, Linux ⬜.

## B. Popup drag-to-reposition  (net-new; Windows leads)

- **Now:** neither platform drags (macOS `isMovableByWindowBackground = false`); the popup always
  snaps to top-center on each show.
- **Change (Windows):** drag the popup by its **card background** — grab anywhere except the action
  buttons (Copy / Close / ◀ ▶); the translation area scrolls via mouse-wheel, so using it as a drag
  surface is fine. Implemented so the `WS_EX_NOACTIVATE` window moves **without** activating / stealing
  focus from the foreground app.
- **Decisions (user-approved):**
  - *Handle:* grab anywhere except buttons.
  - *Position memory:* **session-sticky** — after the first manual drag, later popups appear at that
    position (clamped to the primary work area) until app restart, then back to top-center.
  - *Auto-dismiss:* pauses while dragging, restarts on drop (unless hovering with keep-on-hover).
- **Spec:** §8 shared rule (drag to reposition).
- **Parity:** new row `Popup drag-to-reposition (session-sticky)` §8 — (UI): Win ⬜→✅ (leads),
  macOS ⬜, Linux ⬜. Creates a tracked v0.2 Law-3 entry (expected "one platform leads" pattern;
  no version bump — consistent with the rest of the 0.2 convergence line).

## Verification

No vectors (both UI). `dotnet build sln -c Release` green, then a combined walkthrough with the
earlier #2 work: adaptive size + ◀▶ nav **and** (A) key shows as dots, (B) drag moves the window
without focus-steal, position is remembered, buttons/nav/scroll still work. Then codex cross-review
before flipping the two PARITY rows to ✅.
