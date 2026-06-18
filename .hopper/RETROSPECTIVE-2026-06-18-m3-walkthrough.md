# 复盘 — M3 手动走查发现的问题 (2026-06-18)

> 用户手动走查 macOS app 后发现 3 个核心问题。本文记录每个问题的引入方、当时 review 方、根因分析 + 改进措施。

---

## 问题清单

### A. App 启动后无托盘/无热键/无剪贴板监听（@main 无 nib 未设 delegate）

- **现象**: app 进程存活（PID 在），但菜单栏无 "译" 图标，Force Quit 里无进程，无任何功能。app 是一个空壳 NSApplication（31MB RSS，idle）。
- **根因**: `@main` 在 SwiftPM executable（无 main.storyboard/nib）下合成的 `NSApplicationMain` 只创建 + run `NSApplication`，**不设 AppDelegate 为 delegate** ⇒ `applicationDidFinishLaunching` 从不触发 ⇒ 所有 M3 接线（TrayController/HotkeyService/ClipboardWatcher/Pipeline）都在一个从不被调用的方法里。
- **引入方**: T-MAC-29（kimi）— 创建了 `@main AppDelegate`（App-target 脚手架）。kimi 用了 `@main`（标准 Xcode 模式），但 SwiftPM 无 storyboard 时 `@main` 不设 delegate——这是 SwiftPM+AppKit 的已知坑，kimi 的 spec（T-MAC-29）没有提及。
- **当时 review 方**:
  - 主 session（我）— 审了 T-MAC-29（读了 AppDelegate，确认 `@main` + `.accessory` + 菜单）。**没有发现 `@main` 无 nib 不设 delegate**。我的验收标准是 `swift build` 绿 + `swift test` 22/22——两者都不测 App 启动。
  - Subagent（T-MAC-40）— 审了全部 M3 代码，**没有发现**（代码审查，非运行时）。subagent 审了 no-focus-steal/Carbon/Law-6/supersede 等，但没审 "app 是否真的启动"。
  - mimo（T-MAC-40 首次）— 超时（30min），未出结果。
- **根因分析**:
  - **目标不清晰？** 部分是。spec/PORTING-macos 没有指定 SwiftPM App 的入口模式（`@main` vs `static func main()` vs storyboard）。`@main` 无 nib 的坑是 SwiftPM+AppKit 特有的，spec 没覆盖。→ spec 缺 "SwiftPM AppKit 入口" 的明确指引。
  - **TDD 不清晰？** **是。** 一致性向量测的是 Core 纯逻辑（PromptBuilder/AnsiStripper/...），**不测 App 生命周期**。没有向量/测试验证 "applicationDidFinishLaunching 被调用" 或 "delegate 被设"。TDD 覆盖了 Core（向量全绿），但 App 层（启动/UI/热重载）**没有任何自动化测试**。→ @main bug 对测试套件不可见。
  - **Fable governance 没有 cover 门限吗？** **是——门限的 scope 有缺口。** Fable governance 的 "TDD And Verification" 说 "use a test-first loop" + "Do not claim work is complete, fixed, or passing until the stated verification has actually run." 验证 = `swift test`（116 向量）+ `swift build`。两者都 pass。但**两者都不测 App 启动**。governance 说了 "验证要跑"，但**没说验证的 scope 要覆盖运行时 App 行为**——它把 "什么是充分验证" 推给了任务的 acceptance criteria，而我把 App 任务的 acceptance 设成了 "build + 向量绿"（不包含运行时）。→ **governance 的门限被满足了（验证跑了），但门限的 scope 不够（没覆盖 App 运行时）。** 这是 governance 的应用缺口：对 App 层（无向量）任务，governance 没有强制要求运行时 smoke 验证。

### B. 设置页面保存后不生效（hotReload 未重建 popup；重新打开设置用旧 VM）

- **现象**: 用户改了后端（google-v2）、热键（Ctrl+Alt+C）、浮窗样式（solid）、填了 API Key，点保存。config.json **确实写盘了**（内容正确），但浮窗样式没变（还是 acrylic）、重新打开设置显示旧配置。
- **根因**: `hotReload` 重建了 pipeline + 热键 + watcher，但**没重建 popup**（浮窗样式/autoDismiss 改动不生效）。`openSettings` 用 `if settingsWindowController == nil` 只创建一次 controller，重新打开时复用旧 VM（不反映已保存的配置）。
- **引入方**: T-MAC-36（opencode）— 写了 `hotReload`（重建 pipeline + 热键 + watcher，**漏了 popup**）。`openSettings` 也是 T-MAC-36 写的（只创建一次 controller）。
- **当时 review 方**:
  - 主 session（我）— 审了 T-MAC-36（build+test 绿 + grep 验证接线）。**没有发现 hotReload 漏 popup**——我的 review 聚焦在 supersede/cancel/sandbox/registry 接线，没审 "hotReload 是否覆盖所有需要热重载的组件"。
  - Subagent（T-MAC-40）— 审了 composition，聚焦 supersede/cancel/sandbox，**没审 popup 热重载**。
- **根因分析**:
  - **目标不清晰？** 部分是。spec §9 说 "hot-reloads the running pipeline"——但没枚举所有需要热重载的组件（popup 样式/autoDismiss/keepOnHover）。opencode 把 "hot-reload" 理解为 pipeline + 热键 + watcher，合理但不全。→ spec 没明确 "hot-reload 覆盖哪些组件"。
  - **TDD 不清晰？** **是。** 没有 "设置改 → popup 重建" 的测试。热重载不是向量测试的。→ gap 对测试不可见。
  - **Fable governance？** 同 A——验证是 build+test，不覆盖运行时热重载行为。

### C. UI 太丑，不符合 Mac 设计风格

- **现象**: 浮窗/设置/托盘用了原生 API（NSPanel/NSVisualEffectView/SwiftUI），但排版/字体/间距/控件样式不像 macOS 原生应用——更像 "能跑就行" 的粗糙实现。
- **引入方**: T-MAC-32（opencode — 浮窗）+ T-MAC-34（opencode — 设置）+ T-MAC-33（kimi — 托盘）。都用原生 API，但**没参考 macOS HIG（Human Interface Guidelines）**。
- **当时 review 方**:
  - 主 session（我）— 审了功能正确性（no-focus-steal/vibrancy/states），**没审美学/HIG 合规**。
  - Subagent（T-MAC-40）— 审了正确性，**没审设计语言**。
- **根因分析**:
  - **目标不清晰？** **是——这是主因。** spec §8（浮窗）描述的是**行为**（no-focus-steal/vibrancy/states/hover-keep/auto-dismiss），§9（设置）描述的也是行为（groups/fields/hot-reload）。**两者都没描述美学标准**（字体/间距/控件样式/HIG 合规）。而且 spec 本身是 **Windows-derived**（§8 "acrylic popup"、§9 "Win11 Mica backdrop"——Windows 设计语言）。PORTING-macos 映射了 API（NSPanel→NSVisualEffectView）但**没映射设计语言**。→ builder 没有 macOS 设计 spec 可遵循。
  - **研发框架已经是原生实现，为什么没考虑平台特性？** 原生框架（SwiftUI/AppKit）给的是**构建块**（NSVisualEffectView/NSPanel/NSScrollView），HIG 告诉你**怎么排布**。builder 正确用了原生 API（vibrancy/nonactivating/floating），但**排版/字体/间距/控件样式**没有 HIG 指引。原生 API ≠ 原生设计——没有 HIG 参考，builder 默认到 "make it work" 而非 "make it Mac-native-beautiful"。
  - **设计时为什么没参考 Mac 设计标准？** 因为：(a) spec 是 Windows-derived（从 Windows build 的行为推导），没含 macOS 设计标准；(b) 任务 spec（T-MAC-32/33/34）说 "per spec §8/§9"（行为），没说 "follow macOS HIG"；(c) review 审了行为（no-focus-steal/vibrancy），没审美学；(d) 整条链（spec → task → build → review）**没有人明确要求 macOS HIG 合规**。spec-first（宪法 Law 1）意味着 spec 是事实源——但 spec **没包含** macOS 设计标准。所以 builder 遵循了 spec（行为 only），UI 美学从缝隙中掉了。
  - **TDD 不清晰？** 部分——美学很难 TDD（没有 "看起来像 Mac" 的向量）。但可以有一个 "设计 review" 维度（人工 or checklist）。review 没包含设计检查。
  - **Fable governance？** governance 没要求 "设计合规" 验证——它聚焦 TDD（测试）+ verification（跑通），没覆盖美学/HIG。→ governance 对 "设计质量" 没有门限。

---

## 横切根因（cross-cutting）

1. **Spec 是 Windows-derived** — 设计 spec 为 Windows build 写的（§2 "Windows 11 only"、§8 "acrylic"、§9 "Mica"）。macOS port 复用这个 spec（宪法：同行为跨平台）。但 spec 描述的是 **Windows 行为/美学**，不是 macOS。PORTING-macos 映射了 API 但没映射设计语言。→ macOS port 遵循了 Windows-centric 的行为 spec + macOS API 映射，但**缺乏 macOS 特有的设计指引**。

2. **TDD 覆盖 Core，不覆盖 App** — 一致性向量测纯逻辑（Core）。App 层（启动/UI/热重载）**没有自动化测试**。Fable governance 的 "TDD" 被向量满足了，但 App 层只靠 build + 人工 review 验证，没测试。→ 运行时 bug（@main、热重载）+ 美学问题（UI）从缝隙中掉了。

3. **Fable governance 验证 scope 缺口** — governance 说 "验证要跑"，但**没说验证 scope 要覆盖运行时 App 行为**。它把 "什么是充分验证" 推给了任务 acceptance criteria。我把 App 任务的 acceptance 设成 "build + 向量绿"——不包含运行时。→ governance 的门限被满足了（验证跑了），但门限 scope 不够（没覆盖 App 运行时 + 设计）。

4. **Review 审了正确性，没审设计/运行时** — 交叉审核（mimo/subagent/我）审了功能正确性（no-focus-steal/Law-6/supersede）。**没有审 "看起来像 Mac 吗？" 或 "真的能跑吗？"**。review scope 没包含平台设计合规 + 运行时行为。

---

## 改进措施

1. **加运行时 smoke 测试到 CI** — 启动 app（headless 或脚本）+ 验证 `applicationDidFinishLaunching` 跑了（托盘出现/热键注册）。→ 抓 @main 这类 bug。
2. **Spec: 加 macOS 设计标准** — 更新 design spec 或 PORTING-macos，加 macOS HIG 参考（字体: SF Pro；间距: 8pt grid；控件: 标准 NSButton/NSTextField；materials: vibrancy per HIG；窗口外观）。spec 应明确 "macOS UI 遵循 macOS Human Interface Guidelines" + 具体指引。
3. **任务 spec: 要求 HIG 合规** — macOS UI 任务的 spec 应说 "follow macOS HIG" + 引用 Apple 设计资源。
4. **Review: 加设计检查维度** — 交叉审核应包含 "平台设计" 检查（看起来像 Mac 吗？遵循 HIG 吗？）。可以作为独立 review 维度。
5. **Fable governance: 对 App 任务强制运行时验证** — governance 应要求（App 层任务）运行时验证（app 启动 + 关键流程可用），不只是 build + 向量。加一个 "运行时 smoke" 门限。
6. **Acceptance criteria: 包含运行时** — App 任务的 acceptance = build + 向量 + **运行时**（app 启动 + 功能在运行时可用）。不只是 build + 向量。

---

## 当前修复状态

- **A（@main）**: 已修复（`static func main()` 设 delegate）+ 已提交（`729e68d`）。✅
- **B（设置不生效）**: 已修复（hotReload 重建 popup + openSettings 每次创建新 controller）。待验证 + 提交。
- **C（UI 太丑）**: 待修复（UI polish：参考 macOS HIG 重做浮窗/设置/托盘的排版/字体/间距/控件样式）。

---

## 第二轮走查发现 (hotkey mapping, 2026-06-18)

### D. 热键 "command" 映射为 ⌃ Control 而非 ⌘ Command → 热键不触发弹窗

- **现象**: 用户设热键 "shift+command+c"，按 ⇧⌘C 不弹窗。诊断 (fputs stderr) 显示注册 modifiers=0x1200 (= ⇧⌃C = Shift+Control+C)，非 ⇧⌘C。按键不匹配 → 无回调 → 无弹窗。
- **引入方**: 主 session（我）— commit c26b803 (Ctrl→⌘ / Win→⌃ 重映射)。把 hasWin("Win"/"Command"/"Cmd") 交换到 controlKey(⌃) 是错误的：macOS 用户输入 "command" 期望 ⌘。
- **当时 review 方**: **无审核** — 用户报告问题后的直接修复，未走 vendor 交叉审核。T-MAC-REV 在此修改之前，没覆盖。
- **根因分析**:
  - **目标不清晰？** 部分 — macOS 修饰键映射约定 (Ctrl→⌘, Win→⌃) 是我做的设计决策，spec 没指定。套用"标准移植约定"但 Win/Command 映射搞反。
  - **TDD 不清晰？** **是** — CarbonKeyMapTests 被更新了，但测的是**错误的映射**（我改测试匹配错误实现）。测试验证了实现，没验证**用户期望**（"command" → ⌘）。没有"command → cmdKey"的测试。
  - **Fable governance？** 这次修改没走交叉审核（直接 hotfix）。governance 的 "cross-review" 没覆盖这个 hotfix。
  - **诊断方法有效**: fputs(stderr) + 直接运行 executable 捕获输出 → 立刻定位到 modifiers=0x1200(⇧⌃C) 而非预期的 ⇧⌘C。→ **教训：运行时诊断（stderr print + direct launch）比 NSLog/system log 更可靠**。
- **修复**: hasWin → cmdKey(⌘)，与 hasControl 相同。"Ctrl" 和 "Command" 都 → ⌘。commit bdcf578。

### D 的改进措施

7. **hotfix 也要交叉审核**: 即使是用户报告后的直接修复，也要走 vendor/subagent 交叉审核（至少一次）。
8. **测试验证用户期望，不只是实现**: modifier 映射的测试应该断言 "command → ⌘"(用户期望)，而不是"hasWin → 0x1000"(实现细节)。
9. **运行时诊断优先**: 遇到运行时行为问题，用 fputs(stderr) + 直接运行 executable 捕获输出，比 NSLog/system log 更快定位。

---

## 全量返工日志（A–O 汇总，2026-06-18 整理）

> 覆盖 M3 手动走查 + ZP UI 重设计 + hopper 编排过程中发现的全部返工问题。

### 汇总表

| # | 问题 | 引入方 | 当时 Review 方 | 根因类别 | 修复 commit |
|---|---|---|---|---|---|
| A | @main 无 nib 不设 delegate → app 空壳 | kimi (T-MAC-29) | 主session + subagent (均 missed) | spec 缺 + TDD 缺 + governance scope 缺 | `729e68d` |
| B | 设置保存不生效(hotReload 漏 popup) | opencode (T-MAC-36) | 主session + subagent (均 missed) | spec 模糊 + TDD 缺 | `1d913ea` |
| C | UI 不符合 Mac 设计风格 | opencode (T-MAC-32/34) + kimi (T-MAC-33) | 主session + subagent (均 missed) | spec Windows-derived 缺 HIG + review 缺设计维度 | ZP UI `77cc699`+ |
| D | 热键 command→⌃(映射错误) | **主session** (`c26b803`) | **无**(hotfix 未审核) | 测试验证实现非期望 + hotfix 未交叉审核 | `bdcf578` |
| E | 热键自冲突(checkHotkey 误报自身) | opencode (T-MAC-34) | 主session (missed) | checkHotkey 没跳过当前已注册热键 | `7688ece` |
| F | google-v2 "no translator"(#file 短路径) | opencode (T-MAC-14) | 主session (missed) | release #file 短路径 + build-app.sh 没打包 backends.json | `7688ece` |
| G | ZP 视觉模式(acrylic/solid)不生效 | **主session** (ZPPopup) | subagent (missed) | ZPPopup 固定 .popover 忽略 cfg.style | `7cb2139` |
| H | ZP hover-keep bug(keepOnHover=false 时 hover 杀死 dismiss) | **主session** (ZPPopup) | subagent (**caught** P1) | mouseEntered 无 keepOnHover guard | `ca58261` |
| I | SettingsWindowController.close() build 错误 | **主session** (F4 fix) | **无**(build error 自抓) | 不了解 SettingsWindowController 非 NSWindowController | `8d85989` |
| J | queue.md Brief 含 `|` 破坏表格 | **主session** (queue.md) | **无** | markdown table `|` 未转义 | 改 `/` |
| K | queue.md Depends 范围表示法(T-MAC-10..16) | **主session** (queue.md) | **无** | hopper parser 不支持 range | 改 comma-separated |
| L | mimo review output trap(结果困在 2MB log) | mimo (T-MAC-20/40) | **无**(mimo 是审核者) | read-only sandbox 不能写 output.md + "shall I proceed" gating | 提取自 log / 后续 subagent 替代 |
| M | mimo 大范围审核超时(30min) | mimo (T-MAC-40) | **无** | scope ~15 files + mimo 逐处编辑慢 | subagent 替代 |
| N | stale hopper-dispatch binary(PATH v0.6.1) | hopper 安装(旧 ~/.local/share) | **无** | 双安装 + PATH 指向旧版 | 重指 shim→0.12.0 |
| O | background Bash cwd 不继承 session | **主session** (bg Bash) | **无** | bg Bash 进程 cwd ≠ session cwd | HOPPER_DIR + abs paths |

### 按引入方统计

| 引入方 | 问题数 | 问题 |
|---|---|---|
| **主 session（我）** | 8 | D, G, H, I, J, K, O + C 的 ZP 视觉模式部分 |
| **opencode** | 5 | A(共 kimi), B, C(浮窗+设置), E, F |
| **kimi** | 2 | A(脚手架), C(托盘) |
| **mimo** | 2 | L, M（均为 mimo 审核工具自身限制，非代码 bug） |
| **hopper 安装** | 1 | N |

### 按根因类别统计

| 根因类别 | 问题数 | 具体 |
|---|---|---|
| **spec 不清晰/缺失** | 5 | A(spec 缺 SwiftPM 入口), B(spec 没枚举 hot-reload 组件), C(spec 缺 macOS HIG), D(spec 没指定修饰键映射), E(spec 没说 checkHotkey 要排除自身) |
| **TDD/测试不覆盖** | 6 | A(不测 App 启动), B(不测热重载), D(测试验证实现非期望), E(不测自冲突), F(不测 release bundle), G(不测视觉模式) |
| **Review scope 不够** | 7 | A/B/C(没审运行时/设计), D(hotfix 没审核), E/F(没审边界), G(subagent 没发现视觉模式), H(subagent **发现了** — 唯一 caught) |
| **Fable governance 门限 scope 缺** | 3 | A/B/C(governance 满足"验证跑了"但 scope 不含运行时/设计) |
| **工具/环境问题** | 5 | J/K(queue.md 格式), L/M(mimo 限制), N(stale binary), O(bg Bash cwd) |
| **主 session 实现错误** | 4 | D(映射搞反), G(忽略 cfg.style), H(漏 guard), I(不了解类型系统) |

---

## 新增问题详情 (E–O)

### E. 热键自冲突 — checkHotkey 误报自身已注册热键为冲突

- **引入方**: T-MAC-34（opencode）— 设置窗口的 checkHotkey/tryRegisterHotkey 逻辑。
- **Review 方**: 主 session — 审了 T-MAC-34（功能验证），没审 "checkHotkey 是否排除自身已注册热键"。
- **根因**: checkHotkey 用 tryRegisterHotkey（RegisterEventHotKey + 立即 Unregister）检测冲突，但 app 自身已注册了同一热键 → Carbon 拒绝重复注册 → 误报"冲突"。→ checkHotkey 没跳过当前已注册热键。
- **修复**: checkHotkey 加 `if trimmed == config.hotkey.translate { hotkeyConflict = false; return }`（`7688ece`）。

### F. google-v2 "no translator" — BackendManifest #file 在 release .app 里找不到 spec/backends.json

- **引入方**: T-MAC-14（opencode）— BackendManifest.load() 用 `#file` walk-up 找 spec/backends.json。
- **Review 方**: 主 session — 审了 T-MAC-14（Law-6 验证：确认读 manifest），但**只在 dev 环境验证**（swift run/test），没测 release .app bundle。
- **根因**: Swift release build 里 `#file` 是短模块路径（`TranslateTheDamnCore.BackendManifest`），walk-up 从短路径出发找不到 repo-root 的 spec/backends.json → manifest 未加载 → translator(for:) 返回 nil → MissingTranslator → "没有翻译器"。dev 环境（#file = 全路径）不受影响 → 测试通过 → bug 对 CI 不可见。
- **修复**: BackendManifest.load() 先试 `Bundle.main.url(forResource:"backends",withExtension:"json")`（.app Resources 里的 bundled resource）；build-app.sh 打包 spec/backends.json 进 .app Resources（`7688ece`）。
- **教训**: **release bundle 与 dev 环境的差异**（#file、资源路径、Bundle.main）必须用 release build 验证，不能只靠 dev test。

### G. ZP 浮窗视觉模式(acrylic/solid)不生效

- **引入方**: 主 session（ZPPopup.swift）— ZPPopup 固定 `.popover` material，忽略 `cfg.style`。
- **Review 方**: subagent（T-MAC-REV2）— 审了 ZPPopup，但没发现 cfg.style 未被使用（审了 vibrancy/material 正确性，但没对照 cfg.style 字段）。
- **根因**: ZPPopup 写的时候只关注了 vibrancy 效果（.popover），忘了读 cfg.style 来切换 acrylic/solid。→ 新功能（ZP popup）实现时遗漏了已有的 config 字段（popup.style）。
- **修复**: ZPPopup.setUpContent 检查 `cfg.style`：solid → `.contentBackground` + `.inactive`；acrylic → `.popover` + `.active`（`7cb2139`）。

### H. ZP hover-keep bug — keepOnHover=false 时 hover 永久杀死 auto-dismiss

- **引入方**: 主 session（ZPPopup.swift）— mouseEntered 无条件 invalidate dismissTimer。
- **Review 方**: subagent（T-MAC-REV2）— **发现了**（P1-1）。这是唯一一个被 review **catch 到**的返工问题。
- **根因**: ZPPopup 的 mouseEntered 没有 `cfg.keepOnHover` guard（classic TranslationPopup 有）。keepOnHover=false 时，hover 进入 → 杀死 timer → 永远不重启 → auto-dismiss 永久失效。
- **修复**: mouseEntered 加 `if cfg.keepOnHover { dismissTimer?.invalidate() }`（`ca58261`）。

### I. SettingsWindowController.close() build 错误

- **引入方**: 主 session（vendor review F4 fix）— 我写了 `settingsWindowController?.close()`，但 SettingsWindowController 不是 NSWindowController，没有 close() 方法。
- **Review 方**: 无 — build error 自抓（release build 失败）。
- **根因**: 我不了解 SettingsWindowController 的类型层级（它是自定义 class，不是 NSWindowController）。写 fix 时没查类型。
- **修复**: 移除 close() 调用，改为直接替换 controller（`8d85989`）。
- **教训**: **hotfix 时要查类型/API**，不能假设。

### J. queue.md Brief 含 `|` 破坏表格解析

- **引入方**: 主 session — queue.md T-MAC-36 Brief 写了 `(Clipboard|Hotkey)`。
- **根因**: markdown table 用 `|` 分列，Brief 里的 `|` 被解析为列分隔符 → Vendor 列错位 → "No vendor adapter registered for 'Hotkey)→Popup…'"。
- **修复**: Brief 里的 `|` 改为 `/`（`记录在 COST-LOG`）。
- **教训**: **hopper queue.md Brief cell 不能含 `|`**。

### K. queue.md Depends 范围表示法

- **引入方**: 主 session — queue.md Depends 写了 `T-MAC-10..16`。
- **根因**: hopper parser 把 `T-MAC-10..16` 当作一个 literal ID，不支持 range → "dependency T-MAC-10..16 not found"。
- **修复**: 改为 comma-separated `T-MAC-10,T-MAC-11,...`。
- **教训**: **hopper queue.md Depends 用 comma-separated ID，不用 range**。

### L. mimo review read-only output trap

- **引入方**: mimo（T-MAC-20/40）— mimo 在 read-only sandbox 下运行审核。
- **根因**: mimo 在 read-only 模式下不能写 output.md → 它问 "Shall I proceed with writing the review output?" → gating → hopper 超时/permission-fail → 审核结果困在 2MB raw log 里。→ 审核工作做了但 output 不可用。
- **修复**: 从 raw log 用 python 提取 mimo 的 text/thinking parts → 拿到 findings。后续 M3 review 改用 subagent（不受此限制）。
- **教训**: **read-only sandbox 的审核 vendor 不能写 output → 要么用 write sandbox + 限制路径，要么让 vendor 输出 text（不写文件），要么用 subagent**。

### M. mimo 大范围审核超时

- **引入方**: mimo（T-MAC-40）— M3 审核范围 ~15 文件。
- **根因**: mimo 是 agentic coding tool，逐文件 read→reason→write，~15 文件 + max reasoning → 30min review-tier floor 不够 → timeout。M2 审核只 ~9 文件（373s 完成），M3 ~15 文件超限。
- **修复**: 改用 Claude Code subagent 审核（无超时限制）。
- **教训**: **mimo 审核范围 ≤ ~10 文件；超过用 subagent 或分批 dispatch**。

### N. stale hopper-dispatch binary

- **引入方**: hopper 安装 — `~/.local/share/hopper-plugin` 是旧 v0.6.1（无 mimo），PATH shim 指向它。
- **根因**: 同机两份 hopper 安装（~/.local/share v0.6.1 + 插件 0.12.0），PATH 解析到旧版 → mimo vendor 不可用 → "unknown vendor 'mimo'"。
- **修复**: 重指 shim → 0.12.0 插件二进制（`记录在 ISSUE-stale-dispatch-binary.md`）。
- **教训**: **hopper 安装器应校验 PATH shim 版本 + 避免双安装**。

### O. background Bash cwd 不继承 session

- **引入方**: 主 session — background Bash 用相对路径 `.hopper/...`。
- **根因**: background Bash 进程的 cwd ≠ session cwd（repo root）→ 相对路径解析失败 → "no .hopper/ directory found"。
- **修复**: background Bash 设 `export HOPPER_DIR=<repo>/.hopper` + 用绝对路径。
- **教训**: **background Bash 永远用 HOPPER_DIR + 绝对路径，不依赖 cwd**。

---

## 更新的改进措施（汇总 A–O）

### 流程层面

1. **加运行时 smoke 测试到 CI** — 启动 app + 验证 delegate 被设 + 托盘出现 + 热键注册。→ 抓 A/E/F/G。
2. **Spec 加 macOS 设计标准 + SwiftPM 入口指引** — design spec / PORTING-macos 加 macOS HIG 参考 + `@main` vs `static func main()` 的明确指引。→ 防 A/C。
3. **任务 spec 要求 HIG 合规** — macOS UI 任务 spec 明确 "follow macOS HIG"。→ 防 C。
4. **Review 加设计 + 运行时维度** — 交叉审核包含 "看起来像 Mac 吗？" + "真的能跑吗？"（不只审代码正确性）。→ 防 A/B/C/E/F/G。
5. **Fable governance 对 App 任务强制运行时验证** — App 任务 acceptance = build + 向量 + **运行时 smoke**（不只 build + 向量）。→ 防 A/B/C。
6. **hotfix 也要交叉审核** — 即使是用户报告后的直接修复，也走至少一次 vendor/subagent 审核。→ 防 D/G/H/I。
7. **测试验证用户期望，不只是实现** — 测试断言 "command → ⌘"（期望），不是 "hasWin → 0x1000"（实现）。→ 防 D。
8. **运行时诊断优先** — fputs(stderr) + 直接运行 executable 捕获输出，比 NSLog/system log 更快定位。→ 加速 D/F 诊断。

### 工具层面

9. **release bundle 验证** — CI 或手动用 release build + .app bundle 验证（不只 dev swift test）。→ 防 F（#file 短路径）/ resource 路径差异。
10. **hopper queue.md 格式规范** — Brief 不含 `|`；Depends 用 comma-separated ID（不用 range）；任务行间无空行。→ 防 J/K。
11. **mimo 审核范围 ≤ ~10 文件** — 超过用 subagent 或分批 dispatch。→ 防 M。
12. **read-only 审核 vendor 的 output 策略** — 让 vendor 输出 text（不写文件）或用 write sandbox + 路径限制。→ 防 L。
13. **background Bash 用 HOPPER_DIR + 绝对路径** — 不依赖 cwd。→ 防 O。
14. **hopper 安装校验 PATH shim 版本** — 避免双安装 + stale binary。→ 防 N。

### 主 session 自身

15. **hotfix 时查类型/API** — 不假设类型层级（如 SettingsWindowController ≠ NSWindowController）。→ 防 I。
16. **新功能实现时检查已有 config 字段** — ZPPopup 写的时候要检查 cfg 的所有字段（包括 style）是否被使用。→ 防 G。
17. **复制已有模式的 guard 逻辑** — 新 popup 的 mouseEntered 应对照 classic popup 的 keepOnHover guard。→ 防 H。
