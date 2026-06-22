# RETROSPECTIVE — 跨端对齐机制复盘(2026-06-20)

> 对"跨端契约对齐机制(`docs/CROSS-PLATFORM-PARITY.md`)执行至今"做的一次评估 → 多 agent 蜂巢对抗复核 →
> 修订结论 → 止血 + 留路线。本文是存档与后续 PR 材料。

## 0. 一页结论

机制**主线(契约先行 → 向量逼真 → 落后端对齐)逻辑成立**,缓存那次跑通了真实闭环。但执行暴露两类病:
**(A) 记录滞后/虚标**(PARITY 手维护、UI 项无向量,既会"漏翻 ✅"也会"代码没写却标 🚧"),
**(B) 自动化层环境脆弱**(已收敛)。复核还戳穿一个被高估的点:**Law 2 的"CI 自动逼真"目前是悬空的——
仓库根本没有 CI、开发不走 PR**,对齐靠人自觉跑测试。本次已**止血**:把 6 个 macOS 虚标 🚧 + 1 个 Win 反向
虚标翻 ✅,Dark scrollbar 据实标 `—`;漂移从 27→19、macOS 8→1、Law-3 10→2。剩余按下方路线推进。

## 1. 背景:评估什么

近几日在 macOS 加了两个需求(5 条 MRU 缓存、弹窗自适应+历史导航),全程契约先行;改了共享向量后
Windows 被暴露落后并实际对齐(缓存行 Win 已 ✅)。随后建了 `scripts/parity-drift.py`(漂移报表)+ 会话启动
hook(自动浮现 + 自动建 TODO)。本次评估问:**执行下来有什么需要改进**(用户特别点名"环境识别""记录滞后")。

## 2. 我的初版评估(被审对象)

- 结论:主线成立、闭环属实;P0 stale PARITY(macOS"落后 8 项"中 6 项其实已做没翻 ✅);P1 环境识别(pwsh/
  python3/UTF-8/双 shell,已收敛)+ Python 依赖门槛;P1 双治理文件镜像漂移;P2 平台识别靠猜/Law-3 噪声/
  hook 不能强制动作/并发改 PARITY。
- 方案 Top3:① 止血翻 6 行 ✅;② PR 模板加一行查 PARITY;③ `--verify-vectors`(称"最高价值")。

## 3. 蜂巢复核(3 视角 + 主席)— 已逐条亲验的纠正

| 我原来的说法 | 复核纠正 | 验证证据(亲跑) |
|---|---|---|
| 落后端"被**迫**对齐" | **悬空**:无 CI、零 PR,Law 2 的"CI 自动变红"物理不存在,靠人自觉 | `ls .github/workflows` 不存在;`git log` 全直接 commit、0 PR |
| macOS"落后 8 = 6 已做 + 1 默认热键" | **漏了第 8 项 `Dark scrollbar theme`**;macOS 零实现 → 若顺手翻 ✅ 就是**自造假 ✅** | `grep scrollerStyle/knobStyle/NSScroller` macOS 全树 0 命中 |
| (没提) | **反向 stale**:Win `Popup adaptive size` 标 🚧,但 `popup-sizing` 向量在 Win 已绿、`PopupWindow` 两固定尺寸+◀▶历史已实现 → 应 ✅ | `Conformance.cs:37` 跑 popup-sizing;`PopupWindow.xaml.cs:20/25-91` 有尺寸+历史 |
| "P1 环境已收敛" | 我自己的 `docs/CROSS-PLATFORM-PARITY.md:98` 还写"bash+powershell 两条 entry"(早已改单 bash)——**讲滞后时又漏一处滞后**;"专属配置留 settings.local.json"是设想态 | `docs:98` 原文;`settings.local.json` 仅 disabledMcpjsonServers |
| 方案② PR 模板加一行 | **已存在已失效**:模板 `:13/:14` 早有 `Updated PARITY.md`+`Conformance pass on CI`,stale 照发且根本不走 PR → 软提醒无效,需硬门禁 | `.github/PULL_REQUEST_TEMPLATE.md:13-14` |
| 方案③ `--verify-vectors` 最高价值 | **降级**:只测 7 个逻辑向量,而本次 stale 全是 UI 行(无向量)→ 恰好测不到 | parity-drift 对 UI 行 kind=ui、无 vector 门禁 |

主席 bottom line:主线逻辑成立但 forcing function 悬空;先安全止血(**排除 Dark scrollbar**)+ 修 Win 反向
stale,真正第一优先是**建 CI + 走 PR**,`--verify-vectors` 降级。

## 4. 本次已执行(止血 + 文档修订)

- **PARITY 止血**:macOS `Clipboard watch / Acrylic popup / Popup copy+close / Settings window / Tray icon /
  App icon` 六行 🚧→✅(经源码核实已落地);Win `Popup adaptive size + history nav` 🚧→✅(向量已绿 + UI 已实现);
  `Dark scrollbar theme` macOS 改 `—`(n/a:macOS overlay scrollers 自适应明暗;**不翻 ✅**)。
- **修零散滞后**:`docs/CROSS-PLATFORM-PARITY.md §4.3` 改为"单 bash entry + python 回退 + 专属覆盖留 local"。
- **效果**:`parity-drift --digest` 漂移 **27→19**,macOS **8→1**(仅剩真欠账 Default hotkey),Win **2→1**
  (仅剩 API Key masked),Law-3 **10→2**。报表回归真实。

## 5. 修订后的优先级路线(主席 7 条,后续待办)

| # | 行动 | 量级 | 为什么 |
|---|---|---|---|
| 1 | ✅ **已做** 止血(严格排除 Dark scrollbar)+ 修 Win 反向 stale | S | 让声明追上现实,不制造假 ✅ |
| 2 | **建最小 CI(`.github/workflows`)+ 走 PR** | M | 没 CI,Law 2 的"逼真"全是空头支票;后续一切 CI 依赖方案的地基 |
| 3 | **path-coupled gate**:PR 改了 `platforms/<os>/src/**` 却没动 PARITY 对应列 → CI fail | M | 替代已失效的 PR checkbox,把"记得改 PARITY"变机器阻断;依赖 #2 |
| 4 | **UI 行加证据指针 + 关键交互下沉为向量**(self-write guard/copy/autoDismiss/sizeClass) | M | 唯一对症本次 UI 类 stale 的手段(--verify-vectors 测不到 UI) |
| 5 | `--verify-vectors`(**降级**):先给各端 runner 加 per-vector 结构化输出,再交叉核对"声明✅ vs 真绿" | L | 根治逻辑行虚标;Win `Check.cs` 现仅聚合输出需重构;依赖 #2 |
| 6 | ✅ **已做** 修 `docs:98` 等零散滞后 + 治理镜像单源化 + `strings/` key 一致性 lint(Law 5,现仅 zh-CN) | S | 低成本止漏 |
| 7 | **PARITY 半生成化 + 噪声治理**:逻辑行 ✅ 从向量真值派生(消灭手改 stale + 多 vendor 并发冲突);digest 区分"Linux 整列没开工"vs"新增落后",移植期给 Law-3 baseline 抑制 | L | 让 `--fail-on-drift` 终能上 CI;依赖 #2 #5 |

## 6. 教训

1. **"声明对齐 ≠ 现实对齐"是结构性的,不是个例**:同一根因两个方向——漏翻 ✅(stale)与代码没写却标 🚧
   (虚标),工具(读声明)两头都测不出。UI 行尤甚。
2. **机制自己也会得自己诊断的病**:讲"记录滞后"的文档自身 stale(`docs:98`)。规则文档同样需要 CI/lint 守。
3. **别把"逻辑成立"当"机制存在"**:没有 CI,"向量逼真/落后端自动变红"只是叙事;forcing function 要有人/机器真执行。
4. **对抗复核值钱**:蜂巢戳穿了我自己评估里的夸大与漏判(Dark scrollbar 地雷、反向 stale、无 CI、PR 方案已失效),
   且每条都可亲验。结论越自信,越该被对抗一遍。

## 7. 附:数据

- 止血前:total 27 / macOS 8 / Win 2 / Law-3 10。
- 止血后:total 19 / macOS 1(Default hotkey)/ Win 1(API Key masked)/ Law-3 2 / Linux 17(未开工)。
- 复核工件:`scripts/parity-retro-hive-review-*.js`(4 agents,294k tokens)。

## 8. 执行进展(同会话后续)

按用户"继续推进 完善机制",在止血之后顺路线落地了 forcing function 地基:

- **路线 #2(P0)建最小 CI**:`.github/workflows/conformance.yml` — `macos`(`swift test`,本地实测
  **117 tests 全绿**)/ `windows`(`dotnet run` 离线 harness)各跑同一份 `conformance/` JSON,某端向量
  回归即红;`parity` job 跑报表(仅可见性)。**Law 2 第一次有真 forcing function。** 顺手修了 PARITY/README
  里"run on Windows CI"的自身 stale(彼时根本没 CI)。⚠ 本机 `gh` 未登录,GitHub 上首次 run 结果我看不到,
  需人工瞄一眼 Actions 页(或 `gh auth login` 后我来核)。
- **路线 #3(P1)path-coupled gate**:`scripts/parity-gate.py` + workflow `parity-gate` job(仅 PR)——
  改 `platforms/<os>/src/**` 没动 `PARITY.md` 即 PR 失败,逃生口 `parity:n/a <理由>`。本地用真实历史验证:
  fail 路径 exit 1 命中 `9ba38bd`(纯改 macOS src 无 PARITY),`--warn` 降级 exit 0,逃生正则 OK。
  **诚实修正**:原以为它能抓住 `72cea10` 的 Win popup stale——**抓不到**:`72cea10` *动了* PARITY(翻了
  cache 行),只是 popup 行没翻 ✅。`parity-gate` 只抓"完全忘改 PARITY",抓不到"改了但标错行";后者仍要
  路线 #5/#7(逻辑行 ✅ 从向量真值派生)。这条限制已写进 `docs/CROSS-PLATFORM-PARITY.md §4.5`,不过度宣称。
- **路线 #9(P1)PARITY ⇄ 向量真值交叉核对**:`scripts/parity-verify.py` 关掉 #7/#8 都漏的那类——
  **向量在平台 P 已绿、PARITY 该列却 🚧/⬜**(`72cea10` 欠标)。各端 CI job 内拿 runner **实测**逐向量
  pass/fail 跟 PARITY 该列对账(under-claim / over-claim-red / over-claim-absent),不一致即 job 红。逐向量
  真值由 runner 自吐、**无手维护映射**:macOS 用 `XCTestObservation`(向量名=载入文件名),Windows 用
  `Check.Vector()` 打标;PARITY 解析 import `parity-drift.py`(单源)。**本地实测**:`swift test` 吐
  7 向量全绿 → `parity-verify --platform macOS` 一致 exit 0;并构造 `72cea10` 复现(popup-sizing 绿、行 🚧)
  → 精确报 UNDER-CLAIM exit 1;over-claim(red/absent)、`--warn` 均验证。Windows 端 C# 改动本机无法编译
  (net9-windows + dotnet7),靠 CI 验。已记 `docs §4.6`,并据实标注剩余边界(只覆盖有向量的逻辑行,UI 行仍要 #4)。
- **路线 #4(P1)UI 行证据指针**:`scripts/parity-evidence.py` + `spec/ui-evidence.json` 缩小最后的
  UI 行盲区——每个 UI 行的 ✅ 必须指向实现源码(逐平台 path+symbol),指针悬空/缺失即 CI 红;指针解析但行
  非 ✅ 则 WARN(疑似欠标)。CI 的 `parity` job 校验全平台。**落地即抓出真 stale**:Win `API Key field
  masked` 早在 `72cea10` 就用 `PasswordBox` 实现(读源确认:`TxtApiKey` 绑 `bc.ApiKey`、注释写 masked),
  PARITY 却一直 ⬜——已翻 ✅,**顺带清掉真功能待办 #6**。本机实测:16 个 ✅ UI 声明全部有可解析源、0 unbacked;
  fail 路径(悬空指针)exit 1、`--warn` exit 0 均验证。据实边界:证据指针让 ✅ 可从 diff 审计、防指针腐烂,
  但**不证明行为**(文件在≠功能对);真能机器证明的 UI 交互应下沉成向量(`popup-dismiss` 决策逻辑是下一候选,
  但 CI 不构建视图层,"视图是否真调用"仍需本端构建核对)。
- **路线 #5(真功能)macOS per-platform 默认热键**:spec-first/TDD 落地——先写 RED `tests/PlatformDefaultsTests`
  钉 macOS 默认 = `Ctrl+Shift+C`(经 `CarbonKeyMap` 映射 Ctrl→⌘、Shift→⇧,用户实按 **⇧⌘C / Shift+Command+C**,
  与 Win 同助记字母 C、原生 ⌘ 手感;用户拍板),再改 `ConfigService`/`AppConfig` 默认值转 GREEN,更 spec §7 +
  设置占位符。本机 `swift test` 119 全绿、`swift build`(含视图层)通过。PARITY macOS 该行 ⬜→✅,并按 #4 加
  macOS 证据指针(`parity-evidence` 强制:17 ✅ UI 声明全部有源)。drift:macOS 1→0 behind(仅剩 Linux 整列未开工)。
- **仍欠**:#4 的"下沉向量"另一半(`popup-dismiss` 决策→向量,受限于 CI 不构建视图层)、#7(PARITY 半生成化
  + 噪声 baseline 让 `--fail-on-drift` 能上 CI)、Linux 整列移植。`--verify-vectors` 已被 #9 实质实现,降级归档。
