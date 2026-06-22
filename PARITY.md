# PARITY — feature × platform status

The cross-environment to-do board (Constitution Law 3). A feature is "done" on a platform only when
its **spec entry exists** AND — for logic — its **conformance vector passes on that platform's CI**.
UI/interaction items are verified against the interaction spec + a per-platform UI check.

Legend: ✅ shipped · 🚧 in progress · ⬜ not started · ⚠️ partial/best-effort · — n/a

> **Drift report:** `python3 scripts/parity-drift.py` (`--fail-on-drift` for a CI gate, `--json` for
> machine output). It reads the declarations below — it is **not** a test run; per Law 2 each
> platform's CI vectors remain the truth. "DECLARED-ALIGNED" means the board is self-consistent.

| Feature | Spec | Conformance | Win | macOS | Linux |
|---|---|---|---|---|---|
| Clipboard watch (toggle, self-write guard) | §4, §4.1 | — (UI/OS) | ✅ | ✅ | ⬜ |
| Global hotkey (configurable, conflict-detect) | §4 | `hotkey-parser` | ✅ | ✅ | ⬜ |
| Translation rules / prompt building | §5 | `prompt-builder` | ✅ | ✅ | ⬜ |
| ANSI output cleaning | §6 | `ansi-stripper` | ✅ | ✅ | ⬜ |
| Backends — claude, codex (CLI) | §6 | `spec/backends.json` | ✅ | ✅ | ⬜ |
| Backends — copilot, agy (CLI) | §6 | `spec/backends.json` | ⚠️ | ⚠️ | ⬜ |
| Backends — google-v2, doubao (HTTP) | §6.1/6.2 | `backend-requests` + `spec/backends.json` | ✅ | ✅ | ⬜ |
| Backends — opencode, kimi, mimo (CLI) | §6 | `spec/backends.json` + `effort-tiers` + `doctor-probe` | ✅ | ⬜ | ⬜ |
| Backends — openai-http / anthropic-http (generic HTTP LLM, baseURL+key+protocol) | §6.x (design 2026-06-22) | `backend-requests` | ✅ | ✅ | ⬜ |
| Custom provider (add/delete dialog, baseURL+key, OpenAI/Anthropic protocol radio) | §9 (design) | — (UI) | ✅ | ⬜ | ⬜ |
| Unified target language (`{target}` prompt var, CLI + API; live `/models` enum; CLI/API dropdown tags) | §5/§9 (design) | `config-defaults` + `prompt-builder` | ✅ | ✅ | ⬜ |
| Credential auto-discovery (static-key only, consent-gated; env + opencode + codex) | §9 (design) | `credential-discovery` | ✅ | ✅ | ⬜ |
| Recent-translation cache (5 entries, MRU + recency refresh) | §4.1 | `pipeline-cache` | ✅ | ✅ | ⬜ |
| config.json defaults / bootstrap | §7 | `config-defaults` | ✅ | ✅ | ⬜ |
| Default translate hotkey (per-platform default) | §7 | — (per-platform) | ✅ | ✅ | ⬜ |
| Per-vendor effort-tier selector (manifest tiers + conditional `--effort`) | §6, §9 | `effort-tiers` | ✅ | ⬜ | ⬜ |
| Backend doctor (connectivity/auth probe + live auth lamp) | §9 | `doctor-probe`, `doctor-classify` | ✅ | ⬜ | ⬜ |
| Acrylic popup (no-focus-steal, hover-keep, auto-dismiss, scroll) | §8 | — (UI) | ✅ | ✅ | ⬜ |
| Popup copy + close buttons | §8 | — (UI) | ✅ | ✅ | ⬜ |
| Popup adaptive size (source >500 chars → large) + history nav ◀▶ | §8 | `popup-sizing` | ✅ | ✅ | ⬜ |
| Settings window (backend/model, fields, live hotkey check) | §9 | — (UI) | ✅ | ✅ | ⬜ |
| Tray icon + global switch (persisted) | §3 | — (UI) | ✅ | ✅ | ⬜ |
| App icon = tray glyph (single source) | — | — (UI) | ✅ | ✅ | ⬜ |
| Dark scrollbar theme | — | — (UI) | ✅ | — | ⬜ |
| API Key field masked (secure entry) | §9 | — (UI) | ✅ | ✅ | ⬜ |
| Popup drag-to-reposition (session-sticky) | §8 | — (UI) | ✅ | ✅ | ⬜ |

## Version

| | Win | macOS | Linux |
|---|---|---|---|
| App version | **0.2.0** | **0.2.0** (target — `CFBundleShortVersionString` via T-MAC-51 Info.plist) | — |
| config schema | 1 | 1 | — |

## Notes

- ⚠️ copilot/agy on Windows are best-effort (known Windows `-p` quirks; agy falls back to gemini).
- Conformance coverage: `prompt-builder`, `ansi-stripper`, `hotkey-parser`, `config-defaults`,
  `backend-requests` (google-v2 + doubao request shapes), `pipeline-cache`, `popup-sizing` — run in
  **CI on every push/PR** by each platform's native runner over the same `conformance/` JSON
  (`.github/workflows/conformance.yml`): Windows via `dotnet run` (~150 checks), macOS via
  `swift test` (117 tests). Linux adds its runner when the port starts. *This is the Law 2 forcing
  function — a vector that regresses on any platform turns its job red.*
- The Windows adapters currently **hardcode** the backend definitions that `spec/backends.json`
  declares; refactoring Windows to read the manifest is a tracked future task (keeps the manifest
  the single source for all platforms).
- **PARITY 卫生(2026-06-20,蜂巢复核后止血)**:macOS 的 Clipboard watch / Acrylic popup /
  Popup copy+close / Settings window / Tray icon / App icon 六行此前**虚标 🚧**——本会话已实现并经源码
  核实,翻 ✅;Win 的 *Popup adaptive size + history nav* 行同为**反向虚标**(`popup-sizing` 向量已绿、
  `PopupWindow` 两固定尺寸+◀▶历史已实现),翻 ✅。`Dark scrollbar theme` 的 macOS 列改标 `—`(n/a:macOS
  overlay scrollers 随系统明暗自适应,无需显式实现;Windows 因 WPF 才需显式 theming),**不翻 ✅**。复盘与
  剩余路线见 `.hopper/RETROSPECTIVE-2026-06-20-parity-mechanism.md`。
- **macOS UI consolidated to a single style.** The macOS port experimented with 7 swappable UI
  styles (`uiStyle` switch); it has been consolidated to one finalized "clean" UI (single-page
  grouped Form settings + clean glass-card popup with italic source). The `uiStyle` switch, picker,
  and the other six style implementations were removed. This was macOS-only (never a shared feature),
  so it is not a parity item; `config.general.uiStyle` stays in the schema (nil-default) for
  back-compat. Decision rationale: the UI-style review on branch `expe/202606`.
- **Recent-translation cache extended 1→5 (macOS-first, now matched on Win).** The `pipeline-cache`
  vector was extended (spec §4.1) to pin a 5-entry MRU cache with recency-refresh + LRU eviction;
  macOS implemented it first (vector green). **Windows was caught up** — its 1-entry cache became a
  recency-ordered 5-entry MRU list (`TranslationPipeline`), so `pipeline-cache` is green on Win CI and
  the row is ✅/✅/⬜ — exactly the forcing function closing (Law 2). The separate `popup-sizing` vector
  (spec §8: source > 500 chars → large size) + popup history navigation remains macOS-only (Win ⬜,
  tracked task). Run `python3 scripts/parity-drift.py` for current status.
- **Default translate hotkey is now per-platform (un-pinned from the shared vector).** Previously
  `hotkey.translate` was a single shared default (`Ctrl+Alt+T`) pinned by `config-defaults`. By
  decision it is now **each platform's own choice**: the assertion was removed from
  `conformance/config-defaults.json` (see its `doc` note) and each platform verifies its default with
  a **platform-local** test. **Windows = `Shift+Alt+C`** (`HotkeyConfig.DefaultTranslate`, local test
  green). **macOS = ⬜** — to pick its own platform-appropriate default (likely a ⌘-based one); until
  then it still carries the legacy `Ctrl+Alt+T`. This is a deliberate same-version different-*default*
  case (the hotkey schema/feature is identical across platforms; only the bootstrap default differs).
