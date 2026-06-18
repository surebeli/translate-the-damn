# KM UI 风格独立 Review 报告

**Review 目标**：`translate-the-damn` macOS 端新增第四种 UI 风格 **km**（`KMPopup` + `KMSettingsView`）。  
**Review 性质**：对抗式、独立、只读 review，未修改任何源文件。  
**Review 日期**：2026-06-18  
**Reviewer**：kimi-code subagent（按 `AGENTS.md` / `docs/ZP-UI-REDESIGN-PROMPT.md` 门限执行）

---

## 总体结论

**`needs-fix`**（有 minor 问题需处理，无 blocker/major，不构成合并阻塞但建议修后再发布）。

km 风格在功能、接入、默认策略、编译/测试回归等核心维度均达标；设计门限基本满足。主要扣分项是：**`KMPrimaryButton` 的强调按钮文字使用了硬编码 `NSColor.white`**，违反《设计门限》第 4 条“不写死 RGB、只用系统语义色”的硬性约定；另外存在 2 个 minor/nit 级别的可改进点。所有问题均可在 5 分钟内修复。

---

## 逐条检查结果

### 1. `TranslationPopupUI` 协议完整实现

**结果**：✅ 通过

`KMPopup`（`platforms/macos/src/App/KMPopup.swift`）完整实现了 `TranslationPopupUI` 的全部 6 个方法：

```swift
func showLoading()
func showResult(translation: String, source: String)
func showError(message: String)
func show(source: String, translation: String)
func update(translation: String)
func dismiss()
```

实现路径与 ZP/O48 一致：`show` 转发给 `showResult`，`update` 只刷新 body 与 copy 按钮。

---

### 2. 设计门限满足情况

| 门限 | 状态 | 说明 |
|---|---|---|
| 不抢焦点 | ✅ | `NSPanel(.nonactivatingPanel)`，`canBecomeKey=false`，`canBecomeMain=false`，`level=.floating`，`hidesOnDeactivate=false` |
| 无 darkScrim | ✅ | 仅使用 `NSVisualEffectView`（acrylic→`.popover`/solid→`.contentBackground`），无半透明黑色覆盖层 |
| 系统语义色 | ⚠️ | 主体文字使用 `.secondaryLabelColor`/`.tertiaryLabelColor`/`.labelColor`/`.systemOrange`；但强调按钮文字使用硬编码 `.white`（见问题 M1） |
| 原生材质/控件/SF 字体 | ✅ | `NSVisualEffectView`、原生 `NSButton`、自绘 `KMPrimaryButton`（类似 O48）、`NSFont.systemFont` |
| fade 对称 0.2s | ✅ | 进入/退出均为 0.2s，且带相同垂直位移（`-6pt`），与 O48 思路一致 |
| 对比度 | ✅ | 系统语义色 + vibrancy 材质保证；顶部 accent rail 为 `controlAccentColor` |
| `PopupConfig` 全部生效 | ✅ | `style`（acrylic/solid 切换 material/state）、`autoDismissSeconds`（控制 timer 与 scroll height）、`keepOnHover`（hover 保活）均生效 |
| hover 保活 | ✅ | `mouseEntered` 取消 timer，`mouseExited` 重设 timer，且正确 `guard cfg.keepOnHover` |
| copy 回调 + “已复制 ✓” 1.5s | ✅ | 写入 pasteboard、调用 `onCopy`、1.5s 后恢复文案 |
| 滚动到顶 | ✅ | `showResult` 中 `translationScrollView.contentView.scroll(to: .zero)` |
| source 截断 | ✅ | `truncate(source, max: 400)` + `maximumNumberOfLines=2` + `.byTruncatingTail` |
| 位置稳定 | ✅ | `layoutSubtreeIfNeeded()` + `setContentSize(fittingSize)` + `topCenterOrigin()`，状态切换时重新定位 |

**说明**：`cfg.position` 字段仍未被读取（所有风格都硬编码 top-center），这是与现有风格一致的既有行为，不单独作为 km 的问题。

---

### 3. 强调按钮（`KMPrimaryButton`）在非 key panel + vibrancy 下是否真的会渲染成强调态

**结果**：✅ 会渲染为强调态，结构与 `O48PrimaryButton` 等价。

对比：

| 属性 | `O48PrimaryButton` | `KMPrimaryButton` |
|---|---|---|
| 自绘填充 | `layer?.backgroundColor = controlAccentColor.cgColor` | 相同 |
| 禁用 vibrancy 混合 | `allowsVibrancy = false` | 相同 |
| 圆角 | 7 | 6 |
| 文字颜色 | 硬编码 `.white` | 硬编码 `.white` |
| 尺寸 | 高 24、左右 +28 | 高 22、左右 +24 |

两者在非 key panel 与 vibrancy 环境下都能稳定显示为强调色填充按钮，不会被系统默认 accent highlight 忽略。层级清晰（copy 为填充强调色，close 为 `.rounded` 次要按钮）。

**唯一瑕疵**：`KMPrimaryButton` 没有 pressed/hover 视觉反馈（同 O48），属于 nit。

---

### 4. `KMSettingsView` 字段 / binding / 控件 / uiStyle Picker

**结果**：✅ 通过

- 包含与 ZP/O48/Classic 完全一致的设置字段：监听、热键、后端、模型、API Key/Endpoint/目标语言/源语言、推理强度、回退命令、超时、浮窗风格、自动消失、悬停保活、界面风格、开机自启。
- 使用系统原生控件：`Toggle`、`TextField`、`.roundedBorder`、`SecureField`、`Picker`、`.segmented`、`Slider`、`NavigationSplitView`、`List(selection:)`、`Form`、`.formStyle(.grouped)`。
- 使用 `SF Symbols`：`keyboard`、`cpu`、`macwindow`、`gearshape`，均在 macOS 14 可用。
- uiStyle Picker 已加入 `"km"` 选项（`Text("KM（侧栏）").tag("km")`）。
- 复用同一个 `SettingsViewModel`，binding 行为与其他风格一致。

** minor 差异**：KM 在“触发”页底部多了一句说明文字（与 O48 相同），ZP 没有。这只影响文案冗余，不影响字段 parity。

---

### 5. 接入点是否遗漏

**结果**：✅ 全部接入

| 接入点 | 是否处理 |
|---|---|
| `AppDelegate.createPopup` | ✅ `case "km"` 已加入 |
| `SettingsWindowController.show()` | ✅ `case "km"` 已加入 |
| Classic `SettingsView` Picker | ✅ 已加 `"km"` |
| `ZPSettingsView` Picker | ✅ 已加 `"km"` |
| `O48SettingsView` Picker | ✅ 已加 `"km"` |
| `SettingsViewModel.uiStyle` clamp | ✅ 未知值兜底为 `"O48"`，合法集合含 `"km"` |

---

### 6. 默认策略

**结果**：✅ 通过

- `AppDelegate.createPopup`：`config.general.uiStyle ?? "O48"`，`default` 分支返回 `O48Popup`。
- `SettingsWindowController.show()`：`default` 分支返回 `O48SettingsView`。
- `SettingsViewModel.init`：`uiStyle = config.general.uiStyle ?? "O48"`；非法值 clamp 到 `"O48"`。
- 未把 km 设为默认，保持 nil/未知值 → O48，与宪法“不改 struct 默认值、不改序列化配置”一致。

---

### 7. 回归检查：`swift build` / `swift test`

**结果**：✅ 通过

```bash
cd platforms/macos
swift build       # Build complete!
swift test        # Executed 116 tests, with 0 failures
swift build -c release  # Build complete!
```

`swift build -Xswiftc -warnings-as-errors` 会失败，但失败点在 **既有文件** `platforms/macos/src/Core/PathResolver.swift:128`（`DataBox` 未标记 `@unchecked Sendable`），与 km 风格无关。普通 build/test/release 均干净通过。

---

### 8. 编译 warning / 潜在崩溃点

**结果**：✅ 无崩溃点；⚠️ 1 处既有 warning（与 km 无关）；⚠️ 1 处 km 相关 minor。

- `NavigationSplitView` + `List(selection:)` 在 macOS 14 完全合法，无需额外配置。
- `NSTrackingArea` 使用 `.inVisibleRect`，即使 init 时 `visualEffectView.bounds` 为 `.zero` 也能正确跟踪，与 ZP/O48 一致。
- `NSScreen.screens.first` 为 nil 时返回 `.zero`，不会崩溃。
- 既有 warning：`PathResolver.swift` 的 Sendable 捕获警告（与 km 无关）。
- km 相关 minor：硬编码 `.white` 在 `accentTitle` 中（见问题 M1）。

---

## 发现的具体问题

### M1 — minor：`KMPrimaryButton` 使用硬编码 `NSColor.white`

**位置**：`platforms/macos/src/App/KMPopup.swift:280`

**代码**：

```swift
private func accentTitle(_ s: String) -> NSAttributedString {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    return NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white,   // <-- 硬编码
        .paragraphStyle: para,
    ])
}
```

**违反**：《设计门限》第 4 条“对比度由构造保证 —— 只用系统语义色（`labelColor` 等），不写死 RGB、不加 darkScrim”。O48 也有同样写法，但本次 review 只针对 km；km 作为新风格应遵守更新后的规范。

**建议修复**：使用 `NSColor.labelColor`（在深色/浅色 + vibrancy 下都会自动适配）。若担心浅色模式 accent 上黑色文字可读性，`labelColor` 在 macOS 上面对 accent fill 通常会解析为足够深的颜色；若仍想强制高对比，可改用 `.alternateSelectedControlTextColor`（系统为 selected/强调控件提供的专用文字色）。

```swift
.foregroundColor: NSColor.alternateSelectedControlTextColor
```

> 注：O48 的 `O48PrimaryButton.accentTitle` 同样使用 `.white`，建议后续统一 refactor，但不属于本次 km review 的强制修复范围。

---

### M2 — minor：`KMPopup` 头部使用 `.secondaryLabelColor`

**位置**：`platforms/macos/src/App/KMPopup.swift:121`

**代码**：

```swift
headerLabel.textColor = .secondaryLabelColor
```

**说明**：ZP/O48 的头部均使用 `.labelColor`（更高对比），而 KM 选择 `.secondaryLabelColor` 作为其“muted header”视觉身份。虽然仍在系统语义色范围内，但在某些浅色壁纸 + popover active vibrancy 场景下，对比度余量小于 `.labelColor`。属于设计自由与门限的边界案例。

**建议**：若追求更高可读性，可改为 `.labelColor`；若保持当前视觉层级，建议在实际设备 light/dark 各截图确认对比度达标。不改亦可，但需在验收截图中留证。

---

### N1 — nit：`KMPrimaryButton` 缺少按下 / hover 状态反馈

**位置**：`platforms/macos/src/App/KMPopup.swift:369`

**说明**：按钮当前只有单一 accent fill，按下时无任何变暗/边框变化。O48 同样如此，因此只是 nit。可加 `mouseDown`/`mouseUp` 临时降低 alpha 或切换为稍深的强调色，提升可交互感。

**建议修复（可选）**：

```swift
override var isHighlighted: Bool {
    didSet {
        layer?.opacity = isHighlighted ? 0.8 : 1.0
    }
}
```

---

### N2 — nit：`AppDelegate.createPopup` 注释表述略含糊

**位置**：`platforms/macos/src/App/AppDelegate.swift:211`

**代码**：

```swift
default:  // "O48" + any unknown value → the new default style.
```

**说明**：注释中“the new default style”容易让人误解为 km 是新的默认。实际仍是 O48。

**建议**：改为 `// "O48" + any unknown value → O48 (current default).`

---

## 验证命令及结果

```bash
cd /Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos

# 1. Debug build
swift build
# → Build complete! (0.16s)

# 2. Test suite
swift test
# → Executed 116 tests, with 0 failures (0 unexpected) in 4.330 seconds

# 3. Release build
swift build -c release
# → Build complete! (0.16s)
```

额外执行（非用户要求，但用于排查 warning）：

```bash
swift build -Xswiftc -warnings-as-errors
# → 失败：PathResolver.swift:128 的 Sendable 捕获警告（既有代码，与 km 无关）
```

---

## 结论与下一步

- **状态**：`needs-fix`（minor）。
- **建议 blocking 修复**：无。
- **建议本次合并前修复**：M1（把 `.white` 改为系统语义色，如 `.alternateSelectedControlTextColor`）。
- **建议可选修复**：M2（评估后决定是否改头部颜色）、N1（按钮按下反馈）、N2（注释）。
- **重新 review 触发条件**：若修改 M1，无需 full re-review；若调整 M2 或按钮绘制逻辑，建议再跑一次 `swift build` + `swift test` 即可。
