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
