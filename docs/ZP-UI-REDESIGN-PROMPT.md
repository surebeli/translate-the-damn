# Prompt: ZP 风格 UI 重新设计与开发

> 将此 prompt 完整粘贴到新的 Claude Code session 中即可开始。适用于 translate-the-damn 项目的任何 UI 组件重新设计。

---

## 项目背景

**translate-the-damn** 是一个"复制/热键 → 翻译"工具，目前在 Windows (C#/WPF) 和 macOS (Swift/SwiftUI+AppKit) 双平台运行。项目遵循**宪法驱动开发**（`CONSTITUTION.md`）：spec-first（改行为先改 `/spec` + `/conformance`）、共享向量是唯一事实（`conformance/*.json` 在每平台 CI 全绿）、同 `MAJOR.MINOR` = 同功能集、后端读 `spec/backends.json`（声明式数据，不硬编码）。

macOS 端位于 `platforms/macos/`，技术栈：**Swift（SwiftUI + AppKit），arm64 only，macOS 14+**。SwiftPM 管理（`Package.swift`），两个 target：`TranslateTheDamnCore`（纯逻辑 lib）+ `TranslateTheDamnApp`（AppKit/SwiftUI 可执行）。零外部依赖（Foundation only）。测试用 XCTest（`swift test`），一致性向量在 `tests/Conformance/`。

App 架构：菜单栏 app（`.accessory` policy，无 Dock 图标），单进程。`AppDelegate` 是组合根：`ConfigService → TranslatorRegistry → TranslationPipeline → ClipboardWatcher + HotkeyService → Popup + TrayController + SettingsWindow`。config 在 `~/.translatethedamn/config.json`（schema v1，camelCase，nulls omitted）。

## UI 组件现状

现有 UI（代号 "Classic"）由 hopper vendor（opencode/kimi）实现，存在以下问题：不符合 macOS HIG、视觉粗糙、darkScrim 过重（浮窗像暗框而非毛玻璃）、设置用自定义 CardView 而非原生 Form+Section。这些问题已记录在 `.hopper/RETROSPECTIVE-2026-06-18-m3-walkthrough.md`。

**ZP 风格**是重新设计的 UI，作为默认；Classic UI 保留为可选。切换通过 `config.general.uiStyle`（`"ZP"` 默认 / `"classic"`）+ 设置窗口的 Picker 实现。切换后关闭再打开设置窗即生效（`openSettings` 每次创建新 controller）。

## 设计原则（ZP 风格）

1. **macOS HIG 合规** — 遵循 Apple Human Interface Guidelines。
2. **磨砂半透明** — 大量使用 vibrancy/materials（`NSVisualEffectView` `.popover` / `.contentBackground`，SwiftUI `.ultraThinMaterial`）。
3. **系统语义色** — 只用 `NSColor.labelColor` / `.secondaryLabelColor` / `.tertiaryLabelColor` / `.controlAccentColor` / `.systemOrange` 等。**不用硬编码颜色**（如 `NSColor(white: 0.9, alpha: 1.0)`）。系统色自动适配 light/dark + vibrancy → 保证对比度。
4. **SF Pro 字体** — `NSFont.systemFont(ofSize:weight:)` / SwiftUI 默认字体。不用自定义字体。
5. **原生控件** — `NSButton.bezelStyle = .rounded`、SwiftUI `Toggle` / `Picker` / `Slider` / `TextField` 默认样式。
6. **无 darkScrim** — 让 vibrancy 透出，不用半透明黑色覆盖层。文字靠系统语义色保证可读性。
7. **对比度保证** — 背景色与字体色不能相近。系统语义色 + vibrancy material 自动适配，不需要手动调。
8. **动画** — fade-in（0→1, 0.2s）+ fade-out（1→0, 0.2s）对称。
9. **功能完整** — 新 UI 必须实现旧 UI 的全部功能（states/buttons/hover-keep/auto-dismiss/scroll/copy 等），不能遗漏。

## 实现规范

### 文件结构

- 新 UI 文件命名 `ZP{ComponentName}.swift`（如 `ZPPopup.swift`、`ZPSettingsView.swift`）。
- 旧 UI 文件保留不动（`TranslationPopup.swift`、`SettingsView.swift` 等）。
- 新旧 UI 通过协议共存。

### 协议模式（新旧 UI 共存）

定义一个 `@MainActor` 协议，新旧 UI 都 conform：

```swift
@MainActor
protocol {ComponentName}UI: AnyObject {
    // 声明所有公开方法（show/hide/update/dismiss 等）
}
```

新旧类都 conform：
```swift
final class ZP{ComponentName}: {BaseClass}, {ComponentName}UI { ... }      // 新
final class {ClassicComponentName}: {BaseClass}, {ComponentName}UI { ... }  // 旧（加协议 conformance，不改逻辑）
```

AppDelegate 根据配置选择：
```swift
private func create{Component}(config: AppConfig) -> {ComponentName}UI {
    let uiStyle = config.general.uiStyle ?? "ZP"
    if uiStyle == "classic" {
        return {ClassicComponentName}(cfg: ...) { ... }
    }
    return ZP{ComponentName}(cfg: ...) { ... }
}
```

### Config 字段

- 在 `AppConfig.swift` 的 `GeneralConfig` 加 `uiStyle: String?`（nil → "ZP"，向后兼容旧 config）。
- 设置窗口加 Picker（ZP / Classic），保存到 `config.general.uiStyle`。
- `hotReload` 时根据新 `uiStyle` 重建 UI 组件。

### 浮窗（Popup）具体设计

```
ZPPopup: NSPanel
├── Style: [.nonactivatingPanel, .titled, .fullSizeContentView, .borderless]
├── canBecomeKey = false, canBecomeMain = false  (不抢焦点)
├── level = .floating, hidesOnDeactivate = false
├── isOpaque = false, backgroundColor = .clear, hasShadow = true
├── collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
│
├── NSVisualEffectView (contentView)
│   ├── blendingMode = .behindWindow
│   ├── material = cfg.style == "solid" ? .contentBackground : .popover
│   ├── state = cfg.style == "solid" ? .inactive : .active
│   ├── cornerRadius = 12, masksToBounds = true
│   └── (无 darkScrim)
│
├── NSStackView (vertical, contentStack)
│   ├── headerLabel: systemFont(13, .semibold), .labelColor
│   ├── sourceLabel: systemFont(11), .secondaryLabelColor, maxLines=2
│   ├── translationScrollView (height: min(autoDismiss>0 ? 200 : 280, 280))
│   │   └── translationTextView: systemFont(15), .labelColor, usesAdaptiveColorMappingForDarkAppearance
│   └── buttonStack (horizontal)
│       ├── copyButton: .rounded, .small, systemFont(11, .medium)
│       └── closeButton: .rounded, .small, systemFont(11)
│
├── 状态: showLoading() / showResult(translation:source:) / showError(message:) / update(translation:) / dismiss()
├── Hover: mouseEntered (if cfg.keepOnHover { dismissTimer?.invalidate() }) / mouseExited (if cfg.keepOnHover { restartDismiss() })
├── Auto-dismiss: Timer(autoDismissSeconds), restartDismiss()
├── Fade: showAndPlace (alpha 0→1, 0.2s) / dismiss (alpha 1→0, 0.2s + orderOut)
├── Position: NSScreen.screens.first, top-center
├── Copy: NSPasteboard.general.setString + onCopy callback + "已复制 ✓" 1.5s
└── Strings: StringsLoader["popup.*"] from strings/zh-CN.json
```

### 设置窗口（Settings）具体设计

```
ZPSettingsView: SwiftUI View
├── Form { Section { ... } } .formStyle(.grouped)  (原生 macOS 分组布局)
├── Section "监听与触发": Toggle(listen) + TextField(hotkey) + Label(hotkeyStatus)
├── Section "翻译后端": Picker(backend) + authHint + Picker(model) + conditional fields
├── Section "浮窗展示": Picker(style, .segmented) + Slider(autoDismiss) + Toggle(keepOnHover)
├── Section "通用": Picker(uiStyle, .segmented: ZP/Classic) + Toggle(startWithWindows)
├── Bottom bar: saveStatus + Close button + Save button(.borderedProminent)
├── 系统: 系统色/字体/控件默认样式, 不自定义
└── VM: 复用 SettingsViewModel (@ObservedObject)
```

### SettingsWindowController 切换

```swift
@MainActor func show() {
    let hostingView = NSHostingView(rootView: viewModel.uiStyle == "classic"
        ? AnyView(SettingsView(vm: viewModel))
        : AnyView(ZPSettingsView(vm: viewModel)))
    // ... 创建 NSWindow + contentView = hostingView
}
```

## 开发流程

1. **读契约** — 先读 `CONSTITUTION.md`（法则）、`docs/superpowers/specs/2026-06-17-translate-the-damn-design.md`（行为规格 §3-9）、`platforms/macos/CLAUDE.md`（平台注意事项）。
2. **读现有 UI** — 读旧 UI 文件（如 `TranslationPopup.swift`），理解全部功能/方法/states/hover/timer/copy 逻辑。**新 UI 必须实现全部功能**。
3. **读 config** — 读 `AppConfig.swift`（`PopupConfig` / `GeneralConfig` 等字段），确认新 UI 用到哪些 config 字段（**全部都要用**，不能遗漏如 `cfg.style`）。
4. **实现新 UI** — 新建 `ZP{ComponentName}.swift`，实现协议 + 全部功能 + ZP 设计原则。
5. **加协议** — 定义 `@MainActor protocol {Component}UI`，让新旧 UI 都 conform。
6. **改 AppDelegate** — 加 `create{Component}(config:)` 方法，根据 `uiStyle` 选择新旧 UI。在 `applicationDidFinishLaunching` + `hotReload` 中使用。
7. **加 Config 字段** — 如需新字段（如 `uiStyle`），加到 `AppConfig` 的对应 struct（Optional + 默认值，向后兼容）。
8. **加设置切换** — 在设置窗口加 Picker（ZP / Classic），保存到 config + hot-reload 生效。
9. **验证** — `swift build` + `swift test`（116 tests 全绿，不能回归）。`swift build -c release`（release build 也要过）。`scripts/build-app.sh`（打 .app bundle）。`open TranslateTheDamn.app`（手动走查）。
10. **审核** — 派发 subagent 或 vendor 做第三方审核（检查 HIG 合规、对比度、功能完整、无回归）。

## 验证清单

- [ ] `swift build` 通过（无 error）
- [ ] `swift test` 116/116 green
- [ ] `swift build -c release` 通过（release build 不能漏 #file/Bundle.main 等问题）
- [ ] `scripts/build-app.sh` 成功（.app bundle 生成）
- [ ] `open TranslateTheDamn.app` — app 启动 + 托盘图标出现 + 功能正常
- [ ] 新 UI 功能完整（对照旧 UI 的每个 state/button/hover/timer/copy/scroll）
- [ ] 新 UI 所有 config 字段都生效（特别是 `cfg.style` acrylic/solid、`cfg.autoDismissSeconds`、`cfg.keepOnHover`）
- [ ] UI 切换：设置改 uiStyle → 保存 → 关闭再打开 → 新 UI 生效
- [ ] 系统色在 light/dark 模式下都清晰可读（无对比度问题）
- [ ] vibrancy 透出（无 darkScrim 遮挡）
- [ ] fade-in/fade-out 对称

## 常见坑（已踩过的）

1. **`@main` 无 nib 不设 delegate** — SwiftPM executable（无 storyboard）下 `@main` 合成的 `NSApplicationMain` 不设 AppDelegate 为 delegate → `applicationDidFinishLaunching` 从不触发。必须写显式 `static func main()` 设 delegate + run。
2. **`#file` 在 release build 是短路径** — `BackendManifest.load()` 用 `#file` walk-up 找 `spec/backends.json`，release build 里 `#file` 是短模块路径 → 找不到。必须先试 `Bundle.main.url(forResource:withExtension:)`（.app Resources 里的 bundled resource）。`build-app.sh` 要把 `spec/backends.json` 打包进 .app Resources。
3. **Carbon 修饰键映射** — macOS 上 "Ctrl" → ⌘ Command（cmdKey），"Command"/"Cmd" → ⌘ Command（cmdKey），"Alt" → ⌥ Option（optionKey），"Shift" → ⇧（shiftKey）。不要把 "Command" 映射到 ⌃ Control。
4. **`mouseEntered` 要 guard `keepOnHover`** — 如果 `keepOnHover=false`，hover 进入不应杀死 dismiss timer（否则永久失效）。
5. **`cfg.style` 不能忽略** — 新 popup 要根据 `cfg.style`（acrylic/solid）切换 material，不能固定一种。
6. **`hotReload` 要重建所有 UI 组件** — popup/hotkeys/watcher/pipeline 都要重建，不能只重建 pipeline。
7. **queue.md Brief 不能含 `|`** — markdown table 用 `|` 分列，Brief 里的 `|` 破坏解析。
8. **background Bash 不继承 cwd** — 用 `export HOPPER_DIR=<repo>/.hopper` + 绝对路径。
9. **opencode code-impl 要传 `--sandbox danger-full-access`** — opencode honors sandbox；如果 spec 文本含 "read-only"，hopper 自动设 read-only → opencode 不能编辑。
10. **SettingsWindowController 不是 NSWindowController** — 不要调 `.close()`；要关窗用 `window?.close()` 或直接替换 controller。

## 参考文件

| 文件 | 用途 |
|---|---|
| `CONSTITUTION.md` | 法则 + 指针地图 |
| `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md` | 行为规格 §3-9 |
| `platforms/macos/CLAUDE.md` | 平台注意事项 |
| `platforms/macos/src/Core/AppConfig.swift` | Config 数据结构（PopupConfig/GeneralConfig 等） |
| `platforms/macos/src/App/AppDelegate.swift` | 组合根（createPopup/createSettings + hotReload） |
| `platforms/macos/src/App/TranslationPopup.swift` | 旧浮窗（Classic，参考功能逻辑） |
| `platforms/macos/src/App/ZPPopup.swift` | ZP 浮窗（已实现，参考设计） |
| `platforms/macos/src/App/SettingsWindow.swift` | 旧设置（Classic SettingsView + SettingsViewModel + Controller） |
| `platforms/macos/src/App/ZPSettingsView.swift` | ZP 设置（已实现，参考设计） |
| `platforms/macos/src/Core/BackendManifest.swift` | 后端清单解释器（读 spec/backends.json） |
| `platforms/macos/scripts/build-app.sh` | .app 打包脚本 |
| `strings/zh-CN.json` | 共享文案（StringsLoader 加载） |
| `.hopper/RETROSPECTIVE-2026-06-18-m3-walkthrough.md` | 全量返工日志（15 个问题 + 17 条改进措施） |

---

> **使用方法**：将以上内容粘贴到新 session 的 prompt 中，指定要重新设计的 UI 组件（如"重新设计 ZP 风格的托盘菜单"或"重新设计 ZP 风格的翻译进度条"），新 session 即可依此规范快速上手。
