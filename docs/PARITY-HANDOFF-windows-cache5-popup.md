# Parity handoff — bring Windows up to macOS (5-entry cache + adaptive popup)

> Forward task brief for the **Windows** session. macOS landed two features and updated the
> **shared contracts**; Windows is now behind (proven by `scripts/parity-drift.py`). Your job is to
> make Windows **match the already-updated vectors** — do NOT edit the vectors/spec (they are the
> shared truth; changing them would just push the drift onto macOS).

## 0. Orient (read-only)

```powershell
git pull                                  # get the updated shared contracts
python3 scripts\parity-drift.py           # see exactly what Win is behind on
dotnet run --project platforms\windows\tests\TranslateTheDamn.Tests   # RED on the new vectors
```

`parity-drift` reports **Win 2 behind**:
- `Recent-translation cache (5 entries, MRU + recency refresh)` → `make conformance/pipeline-cache.json pass on Win`
- `Popup adaptive size (>500 chars → large) + history nav` → `make conformance/popup-sizing.json pass on Win`

The shared contracts driving this (already on `main`, do not change):
- **spec §4.1** — cache is now up to **5 entries**, MRU, recency-refresh on hit, LRU eviction.
- **spec §8** — popup has **exactly two fixed sizes** (large = 2× width × 1.5× height; chosen when the
  displayed entry's source > 500 chars; window snaps to one of two, content scrolls inside) + **◀ ▶
  history navigation** over the cache (one entry at a time, never re-invokes the model).
- **conformance/pipeline-cache.json** — 3 scenarios (basic hit/miss, capacity-5 + LRU eviction,
  access-refreshes-recency).
- **conformance/popup-sizing.json** — `sizeClass(sourceChars)` → `normal`/`large` (strict `> 500`).

## 1. Logic (Core) — gated by conformance vectors (Law 2 = must go green)

### 1a. 5-entry MRU cache — `platforms/windows/src/TranslateTheDamn.Core/TranslationPipeline.cs`
Today `_cache` is a single `CacheEntry?`. Change to a recency-ordered list (newest first), capacity 5:
- Field: `private readonly List<CacheEntry> _cache = new();` (guarded by `_gate`). `Update(...)` clears it.
- In `RunAsync`, the **hit** path: find the entry matching `(text, backendId, model)`; if found, **remove
  it and re-insert at index 0** (refresh recency) and return `entry.Result` without calling the model.
- The **miss-success** path: `_cache.Insert(0, new CacheEntry(text, backendId, model, result));` then
  `if (_cache.Count > 5) _cache.RemoveAt(_cache.Count - 1);` (evict least-recently-used).
- Add `public IReadOnlyList<(string Source, string Translation)> RecentHistory()` → newest→oldest
  `(_.Text, _.Result.Text)` (snapshot under `_gate`); the App layer feeds it to the popup.

> The Windows runner (`tests/.../Conformance.cs` `RunCacheScenariosAsync`) already loops the
> `scenarios` generically, so once the impl is 5-entry MRU the new scenarios pass with **no runner
> change**. Mirror the Swift logic in `platforms/macos/src/Core/TranslationPipeline.swift`.

### 1b. Popup size decision — new `platforms/windows/src/TranslateTheDamn.Core/PopupSizing.cs`
Pure function mirroring `platforms/macos/src/Core/PopupSizing.swift`:
```csharp
public static class PopupSizing
{
    public const int  LargeSourceCharThreshold = 500;   // strict > 500 → large
    public const double LargeWidthFactor  = 2.0;
    public const double LargeHeightFactor = 1.5;
    public static string SizeClass(int sourceChars) => sourceChars > LargeSourceCharThreshold ? "large" : "normal";
}
```

### 1c. Add the popup-sizing conformance check — `platforms/windows/tests/TranslateTheDamn.Tests/Conformance.cs`
`popup-sizing.json` is NOT wired yet. Add a check (call it from `RunAsync`) that loops its `cases`:
read `case["in"]["sourceChars"]` (int) + `case["out"]` (string), assert `PopupSizing.SizeClass(...)` equals it.
(Pattern: copy any existing scalar-`cases` check in this file; same as macOS `PopupSizingTests.swift`.)

## 2. UI (App) — per spec §8, verified by a per-platform UI walkthrough (no vector)

### 2a. Adaptive size + history nav — `platforms/windows/src/TranslateTheDamn.App/UI/PopupWindow.xaml(.cs)`
- **Exactly two fixed window sizes.** Define `normal` (W×H) and `large = (2·W, 1.5·H)`. Pick by the
  **currently displayed entry's** source length via `PopupSizing.SizeClass`. The window is exactly one
  of the two — do **not** auto-size to content; let the translation **scroll inside** and cap the source
  at 2 lines, so different content lengths never produce a third size. (This was the macOS bug: using
  fit-to-content made every record a different height — see commit `3a51833`. Don't repeat it.)
- **History navigation**: ◀ older / ▶ newer buttons + an `i / n` indicator; show one entry at a time
  (newest = just-queried first); disable at the ends; navigating re-renders from the cache snapshot and
  **never calls the model**. Recompute the size on each displayed entry.

### 2b. Feed history to the popup — `platforms/windows/src/TranslateTheDamn.App/AppController.cs`
After a successful `RunAsync`, pass `pipeline.RecentHistory()` to the popup (show index 0 = newest).
Mirror macOS `AppDelegate.translate` → `popup.showResults(history, index: 0)`.

## 3. Verify + record (definition of done)

1. `dotnet run --project platforms\windows\tests\TranslateTheDamn.Tests` → **all green** (the updated
   `pipeline-cache` + new `popup-sizing` checks pass). This is the Law-2 truth for the logic.
2. UI walkthrough: source > 500 chars → **large** window; ≤ 500 → **normal**; ◀ ▶ switches entries and
   the window only ever toggles between the two fixed sizes (never an in-between).
3. Edit `PARITY.md`: flip **Win** to ✅ on both rows:
   - `Recent-translation cache (5 entries, MRU + recency refresh)`
   - `Popup adaptive size (source >500 chars → large) + history nav ◀▶`
4. Re-run `python3 scripts\parity-drift.py` → **no Win-behind on these rows**, and the two
   `v0.2 … shipped on macOS but NOT on Win` Law-3 violations clear. That closes the loop.

## Reference (macOS implementation to mirror)
- Cache: `platforms/macos/src/Core/TranslationPipeline.swift` (`recentHistory()`, MRU + LRU evict).
- Size rule: `platforms/macos/src/Core/PopupSizing.swift` + test `tests/Conformance/PopupSizingTests.swift`.
- Popup (two fixed sizes + nav): `platforms/macos/src/App/DSPopup.swift` (`applySize`, `showAndPlace`
  snapping to a fixed spec; `showResults`/`renderCurrent`/`onPrev`/`onNext`).
- App wiring: `platforms/macos/src/App/AppDelegate.swift` (`recentHistory()` → `showResults`).
