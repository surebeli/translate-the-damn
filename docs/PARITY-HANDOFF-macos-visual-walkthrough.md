# PARITY handoff — visual walkthrough (config + popup), macOS mirror

**Status:** Windows ✅ landed & verified (clean Release build, 325/325 conformance). macOS ⬜ to be
walked through on the macOS mirror (owner: user).

This is a **per-platform UI-polish** pass: disabled-button affordances, error/process/success state
colours, contrast, and layout. **No shared contract is touched** — no `spec/`, no `conformance/`, no
`strings/` change (the visible strings already exist on both platforms). Colours are a per-platform
choice (Constitution line 7, "native per platform"); what this handoff makes a **parity contract is the
state→semantics mapping**, not the literal hex. Each platform expresses the same semantics with its
own idiomatic palette (Windows: explicit dark-theme hexes; macOS: system semantic colours).

## The state→semantics contract (both platforms must honour)

| State | Semantic | Windows hex (reference) | macOS idiom |
|---|---|---|---|
| success / ready / pass | calm green | `#8FE3C0` | `.green` / accent |
| error / fail / not-ready | warm red | `#FFB4A9` (single-sourced) | `.red` (one token, reused) |
| degraded / warning | amber | `#E8C07A` | `.orange` |
| in-progress / neutral info | neutral gray | `#C9C9C9` | `.secondary` + spinner |
| idle (empty status) | — | (no colour) | `.secondary` |

Rule: **a control that can be in a failure state must read as failure** (colour *and* glyph/wording),
and a **transient confirmation must revert** (not become a sticky label). The Windows defect class was
"status text locked to one colour regardless of state"; macOS has the **same class** in three places
(everything is `.foregroundStyle(.secondary)`).

## What the Windows pass fixed (10 findings, all code-verified)

P1 — auth lamp coloured by readiness; popup source text contrast (`#90AAAAAA`→`#B0B0B0`).
P2 — invalid-hotkey status red; copy button "已复制 ✓" reverts after 1.5 s; popup backend-id contrast
(`#88AAAAAA`→`#B8B8B8`); error-red **unified** on `#FFB4A9` across settings + popup + delete; empty-source
popup hides the stray divider.
P3 — popup ◀/▶ dim when disabled (popup window got its own disabled-dim `Button` style); loading body
gray single-sourced to `#C9C9C9`; hotkey-status vertical spacing.

## macOS: where each finding maps (file:line are current on the mirror at handoff time)

**Applies — needs work (same defect class):**

1. **Auth lamp colour** (Win `auth-lamp-no-error-color`). macOS `authHint` is a plain `String`
   (`SettingsWindow.swift:90`), set in `refreshAuthHint()` (`SettingsWindow.swift:410-424`) with the
   "● 未配置 API Key…" / "● 未找到命令…" failure text, and rendered `.foregroundStyle(.secondary)`
   (`DSSettingsView.swift:93`). → Add an `authReady: Bool` (or a small status enum) set alongside the
   string in `refreshAuthHint`, and colour the `Text` red when not ready, green when ready.
2. **Invalid-hotkey colour** (Win `hotkey-invalid-no-error-color`). `hotkeyStatus`
   (`DSSettingsView.swift:51-74`) falls back to `.secondary` (line 74). → Drive an invalid/parse-error
   state to `.red`, valid to `.green`.
3. **Save-status colour** (Win — the original request). `vm.saveStatus` (`SettingsWindow.swift:89`) is
   rendered `.foregroundStyle(.secondary)` (`DSSettingsView.swift:258`) for every state incl. the
   "保存失败: …" path (`SettingsWindow.swift:449`) and "已存在 / 内置不可删除" (`:248,:261`). → Add a
   `saveStatusKind` (ok/error/info) set at each assignment site (`:221,:248,:255,:261,:267,:274,:293,:445,:449`)
   and colour the `Text` accordingly.
4. **One error-red token** (Win `error-red-three-way-drift`). When adding the reds above, define **one**
   error colour and reuse it for save-status, auth lamp, and hotkey — don't introduce three.
5. **Copy confirmation reverts** (Win `popup-copied-no-reset`). `strings`/`popup.button.copied` = "已复制 ✓"
   (`StringsLoader.swift:61`). → Verify the macOS popup restores `popup.button.copy` after a delay while
   the same result stays on screen; add a one-shot reset if it sticks (mirror of `_copyResetTimer`).

**Already handled by macOS native semantics (verify, likely no change):**

- **Popup text contrast** (Win `popup-sourcetext` / `popup-statustext`): macOS uses
  `.secondaryLabelColor` (`DSPopup.swift:191,235,445`) which the OS keeps legible in dark mode — no
  alpha-on-near-black trap like the Windows `#88/#90` ARGB. Spot-check only.
- **Disabled ◀/▶ dim** (Win `popup-prevnext-no-disabled-dim`): `NSButton` dims when `isEnabled=false`
  natively. No style needed.
- **Empty-source divider** (Win `popup-empty-source-stray-divider`): macOS already sets
  `sourceLabel.isHidden = true` on the error path (`DSPopup.swift:375`). Confirm there's no separate
  always-visible divider; if there is, hide it together with the source.
- **Loading body gray / loading state** (Win `loading-gray-drift`): macOS shows a spinner via
  `setHeader(loading:)` + `.systemOrange` error body (`DSPopup.swift:376`) — distinct states already.
- **Layout/spacing** (Win `settings-hotkey-card-double-hint-spacing`): SwiftUI `Form` spacing is native;
  walk it but expect no change.

## Acceptance for the macOS pass

- Settings: save success = green, save/validation failure = red, neutral info = secondary; auth lamp and
  hotkey status colour by state; one error colour reused (not three).
- Popup: failure header/body read as error; copy confirmation reverts; source+divider both hidden when
  no source.
- `swift build` + `swift test` green (no new vectors — this pass adds none); CI macOS runner green.
- Update `PARITY.md` only if a *feature* row changes (this pass doesn't add features); otherwise no
  parity-matrix edit is required.
