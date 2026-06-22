# 跨端契约对齐机制 (Cross-Platform Parity)

> 让 **native-per-platform**(每端原生、不共享 UI/runtime 代码)的项目,在不牺牲原生体验的前提下
> **自动发现并消除跨端漂移**。本文是这套机制的背景、诞生过程、用法与意义,可作为相关 PR 的说明材料。

**一句话**:改共享行为先改契约(`/spec` + `/conformance`),向量在每个平台跑绿才算 done(Law 2);
某端落后会被 `scripts/parity-drift.py` 一条命令列出,并在**会话启动时自动浮现、自动建成 TODO**——
不靠记性、不用手动跑测试。

---

## 1. 背景:为什么需要它

本项目是 **native per platform**(Windows = C#/WPF,macOS = Swift/SwiftUI+AppKit,Linux 待做),
宪法明确**不共享 UI/runtime 代码**——原生换来最佳的性能、手感与平台规范一致性,但代价是:

> **一端改了行为或加了功能,另一端不会自动知道 → 跨端漂移。**

传统靠"人记 + code review"对齐,在多端、长周期下必然漂移。本仓库的宪法给出的答案不是"共享二进制",
而是用**共享契约 + 语言中立向量 + parity 看板**来强制一致(`CONSTITUTION.md` Law 1/2/3/6):

- **Law 1 — spec-first**:改共享行为,先改 `/spec` 与 `/conformance`,再写平台代码。
- **Law 2 — 向量即唯一事实**:逻辑的"完成"判据 = 它的 `conformance/*.json` 向量在**那个平台的
  CI/runner 跑绿**。改了向量 → 落后端测试自动变红,这是防漂移的"逼真"机制。
- **Law 3 — 同 `MAJOR.MINOR` = 同功能集**:差异登记在 `PARITY.md`。
- **Law 6 — 后端不写死**:后端调用读 `spec/backends.json` 声明式清单。

这套机制把"漂移"从**靠记性 / 靠手动跑全套测试才能发现**,升级为**一条命令的报表 + 会话启动自动浮现 +
自动建 TODO**。

---

## 2. 组成:这套契约由什么构成

| 角色 | 文件 | 作用 |
|---|---|---|
| 法则 + 指针地图 | `CONSTITUTION.md` | 不可违背的法则,指向所有共享件 |
| 行为规格 | `docs/superpowers/specs/*-design.md`(`/spec`) | 跨端共享的行为定义 |
| **语言中立向量** | `conformance/*.json` | 唯一事实;每端写薄 runner 喂同一份 JSON 断言 |
| 后端清单 | `spec/backends.json` | 声明式后端定义(所有端读它) |
| 共享文案 | `strings/zh-CN.json` | UI 字符串单一来源 |
| **功能×平台看板** | `PARITY.md` | 每功能在 Win/macOS/Linux 的 ✅/🚧/⬜/⚠️/— |
| **漂移报表** | `scripts/parity-drift.py` | 读上面这些,输出各端落后清单 + 动作 |
| **自动浮现** | `.claude/settings.json` hooks + `CLAUDE.md`/`AGENTS.md` 会话启动仪式 | 启动即提醒 + 自动建 TODO |
| 跨端交接 | `docs/PARITY-HANDOFF-*.md` | 给落后端的逐文件任务简报 |

---

## 3. 诞生过程:它是怎么被逼出来的

这套机制不是凭空设计,而是在一次真实的 macOS 开发中**被需求逼出来、并被踩坑打磨**的:

1. **在 macOS 加两个需求**(翻译结果缓存 1→5 条 MRU、弹窗源文 >500 字用大尺寸 + 历史导航),
   全程按 spec-first 走:先改 `/spec §4.1/§8`,再扩 `conformance/pipeline-cache.json`、新增
   `conformance/popup-sizing.json`,最后实现 + `swift test` 全绿。
2. **改了共享向量,Windows 的旧实现就"按契约必然落后"**(它还是 1 条缓存,跑不过新的 5 条向量场景)。
3. **痛点显现**:要发现"Windows 落后了"得手动跑各端测试,或自己记着去翻 `PARITY.md` —— 麻烦、易漏。
4. **造 `parity-drift.py`**:一条命令读 `PARITY.md` + `conformance/` + `spec/backends.json`,输出
   "各平台落后于已发布对端的清单 + 每项下一步动作 + Law 3 显式校验(同版本却功能集不同)"。
   该脚本经 **3 路对抗审查**(解析健壮性 / 漂移判定逻辑 / CI 实用性)加固后才定稿。
5. **再进一步:连脚本都不想手动跑** → 用 Claude Code 的 SessionStart hook 自动跑 + 把摘要注入会话。
6. **跨平台踩坑(本身就是 PR 价值)**:
   - `python3` vs `python`(Windows 常是后者);
   - 默认 shell:macOS=bash、Windows=PowerShell(bash 语法在 PS 里整条非法);
   - 输出编码:摘要含中文+emoji,Windows 控制台默认非 UTF-8 → 崩溃(已强制 UTF-8);
   - 两 shell 都在 → 重复触发(用 session 级原子标记去重);
   - **关键发现**:`SessionStart` 注入的指令,模型只**显示**、不主动调工具(那时没有"活跃回合");
     把"建 TODO"的祈使指令挪到 **`UserPromptSubmit`**(用户第一条真实消息的回合),模型才真正动作。
   这段"踩坑 → 修正"恰好证明了机制的健壮性边界与最终形态。

---

## 4. 使用方式

### 4.1 改一个共享行为(开发循环)

```
改 /spec + /conformance(先)  →  在本端实现到向量跑绿(Law 2)  →  更新 PARITY.md  →  跑 parity-drift 确认
```
绝不先改平台代码再补契约;也绝不在落后端"改向量来让自己变绿"(那只会把漂移甩给别人)。

### 4.2 看漂移(一条命令)

```bash
python3 scripts/parity-drift.py              # 完整报表:各端落后清单 + 动作 + Law3 + 向量覆盖 + spec 缺口
python3 scripts/parity-drift.py --digest     # 紧凑摘要(会话启动用)
python3 scripts/parity-drift.py --json       # 机器可读(CI 消费,含 has_drift/result/summary)
python3 scripts/parity-drift.py --fail-on-drift   # 有漂移则 exit 1 —— 可直接做 CI gate
python3 scripts/parity-drift.py --strict     # 把孤儿向量 + "已落地却无 spec" 也纳入 gate
```
> Windows 上把 `python3` 换成 `python` 或 `py`(脚本需已装 Python)。

每个落后项都带**可执行动作**:逻辑项 → `make conformance/<vector>.json pass`;后端 → 读
`spec/backends.json`;UI 项 → 按 spec § + 人工走查。

### 4.3 自动浮现(零操作,Claude Code)

`.claude/settings.json`(团队共享、**平台中立**)注册两个 hook,每个**单条 `shell: bash` entry +
`python3 → python` 解释器回退**(Claude Code 在各平台都提供 bash;真正平台专属的覆盖——如无 Git Bash 的
Windows 加 powershell 条——放各机 `.claude/settings.local.json`(gitignored),不进共享文件):

- **`SessionStart`**(`--hook`):会话一开,把待办摘要作为 `systemMessage` **显示给你**。
- **`UserPromptSubmit`**(`--hook-act`):在你**第一条消息**的回合注入祈使指令,让 agent **自动把当前
  平台的落后项逐条建成 TODO** 并告知数量。(`UserPromptSubmit` 每条消息触发,脚本按 `(session, tag)`
  原子去重,确保每会话只浮现一次。)

非 Claude Code 的 agent(读 `AGENTS.md`,如 Fable)没有 hook,但 `AGENTS.md`/`CLAUDE.md` 的
**「会话启动仪式」**指引它**自己**跑一次 `parity-drift.py --digest` 并据此建待办——所以"启动即被告知
待办"对任意 agent 都成立。

> 边界:hook 能**可靠显示**待办,但**不能强制**模型创建任务对象——那一步仍取决于模型(首回合注入命中
> 率高,但非 100%)。兜底:摘要照常显示 + 对 agent 说一句「建TODO」即可。

### 4.4 把一个功能对齐到另一个平台(闭环)

```
对端 git pull(拿到已更新的共享契约)
  → python3 scripts/parity-drift.py        # 看本端落后哪些
  → 跑本端 conformance runner               # 改过的向量会让它变红(Law 2 逼真)
  → 按 docs/PARITY-HANDOFF-*.md 实现到向量全绿
  → 把 PARITY.md 对应行该平台翻 ✅
  → 重跑 parity-drift,确认不再 behind、Law-3 违例消失      # 闭环
```
交接简报示例见 `docs/PARITY-HANDOFF-windows-cache5-popup.md`(逐文件 + 验收门禁)。

### 4.5 CI:把契约从"叙事"变成"强制"(2026-06-20)

这套机制曾有个被 2026-06-20 蜂巢复核戳穿的空洞:**仓库没有任何 CI、开发直推 main**——Law 2 的"向量在
各端 CI 跑绿、某端回归就变红"只是文档里的话,真正靠人自觉跑 runner。现已落地最小 CI
(`.github/workflows/conformance.yml`),每次 push/PR 跑:

- **`macos` / `windows` job**:各端原生 runner(`swift test` / `dotnet run` 离线 harness)跑**同一份**
  `conformance/` JSON。某端向量回归 → 该 job 红。**这就是 Law 2 缺失已久的 forcing function。**
- **`parity` job**:`parity-drift.py` 报表(仅可见性,不硬门禁——Linux 整列未开工 + 移植期 Law-3 delta
  会让 `--fail-on-drift` 永红;硬门禁见路线 #7)。
- **`parity-gate` job(仅 PR)**:`scripts/parity-gate.py`——改了 `platforms/<os>/src/**` 却没动
  `PARITY.md`,**该 PR 失败**(替代早已被证伪的 PR checkbox)。行为中性改动(重构/注释)用 commit
  message 写一行 `parity:n/a <理由>` 放行,**逼一次有意识判断**而非无脑勾选。

> 边界(据实,别过度宣称):`parity-gate` 只抓"**完全忘了改 PARITY**"(历史里真有,如纯改 macOS src 的
> 提交);它**抓不到**"改了 PARITY 但某行标错"——例如向量已绿、行却还是 🚧(`72cea10` 正是如此)。**那一类
> 由下面 §4.6 的 `parity-verify` 关掉。**
>
> 另:`parity-gate` 只在 **PR** 上触发——直推 main 不受约束,所以"走 PR"是这道门生效的前提(也是复核建议)。
> 本端合并前可手动 `python3 scripts/parity-gate.py` 自查。

### 4.6 PARITY ⇄ 向量真值交叉核对(2026-06-22,关掉 72cea10 盲区)

#7(向量回归→job 红)+ #8(忘改 PARITY→PR 红)都漏掉一类:**某逻辑行的向量在平台 P 已绿,PARITY 该平台列
却还是 🚧/⬜**(欠标)。#7 不触发(job 是绿的)、#8 不触发(PARITY 也许动了,只是动错格)——这正是
`72cea10`(`popup-sizing` 在 Win 已绿、行却 🚧)当初要靠手工修的那类。

`scripts/parity-verify.py` 关掉它:在**各端自己的 CI job 内**(那是唯一能观测到该端向量真伪的地方),拿该端
runner **实测**的逐向量 pass/fail 跟 PARITY 该列对账,对每个逻辑行:

- 向量**绿**但列非 ✅ → **UNDER-CLAIM**(`72cea10` 反向 stale,job fail)
- 列 ✅ 但向量**红** → OVER-CLAIM(同时也被 #7 抓)
- 列 ✅ 但该端 runner **根本没跑**这个向量 → OVER-CLAIM(给没测的功能标绿)

逐向量真值由 runner 自己吐(**无手维护映射**——drift 不会再生):
- macOS:`tests/Conformance/ConformanceResults.swift`(`XCTestObservation`),向量名就是 `loadVector(...)`
  载入的文件名,各 conformance test 一向量;`TTD_EMIT_RESULTS` 置位时写 `conformance-results.macos.json`。
- Windows:`Check.Vector(stem)` 给每段 conformance 块打标,`Check.WriteResults(...)` 写
  `conformance-results.windows.json`。
- PARITY 解析直接 import `parity-drift.py`(**单一事实源**,两个工具不会对一行的含义产生分歧)。

CI 里 `macos`/`windows` job 跑完向量后各自 `parity-verify --platform <P>`;不一致即该 job 红。本机自查:
`TTD_EMIT_RESULTS=/tmp/r.json swift test && python3 scripts/parity-verify.py --platform macOS --results /tmp/r.json`。

> 仍有边界:只覆盖**有向量的逻辑行**;**UI 行**(剪贴板监听/浮窗/托盘等无 language-neutral 向量者)
> `parity-verify` 管不到——那一块由下面 §4.7 的证据指针缩小。

### 4.7 UI 行证据指针(2026-06-22,缩小 UI 盲区)

UI 行没有 language-neutral 向量(亚克力模糊、不抢焦点、托盘、安全输入框……都是真·视图层),`parity-verify`
够不着。`scripts/parity-evidence.py` 缩小这块:**每个 UI 行的 ✅ 必须在 `spec/ui-evidence.json` 里指向实现
它的源码**(逐平台 `path` + 可选 `symbol`),checker 校验指针**解析得到**(文件在、符号在):

- ✅ 但无指针 / 指针悬空(文件没了、符号找不到)→ **CI 红**(声明了却无法被 reviewer 核对)
- 指针**解析成功**但该平台行**非 ✅** → **WARN**(疑似欠标;文件在 ≠ 行为对,需人确认后再翻)

CI 的 `parity` job(Ubuntu,整树都在)跑 `parity-evidence.py` 校验全平台指针。本机自查:`python3
scripts/parity-evidence.py`。落地即见效:它**当场抓出 Win `API Key field masked` 欠标**——Win 早在
`72cea10` 就用 `PasswordBox`(`TxtApiKey` 绑 `bc.ApiKey`、注释明写 masked)实现了,PARITY 却一直 ⬜;
读源确认后已翻 ✅(顺带清掉真功能待办 #6)。

> 据实边界(别过度宣称):证据指针让 ✅ **可从 diff 审计**、并防指针自身腐烂,但**不证明行为正确**——
> 文件在不等于功能对,那仍要 spec + 人工 UI 走查。真正能机器证明的 UI 交互,应**下沉成向量**(如
> `popup-sizing` 已做;`popup-dismiss` 自动消失/悬停保留的**决策逻辑**是下一个候选——纯函数、跨端一致、
> 可向量化;注意 CI 只构建各端 Core+runner,**不构建 WPF/SwiftUI 视图层**,故"视图是否真调用该决策"仍需本端构建核对)。

---

## 5. 意义:为什么这对原生开发有帮助

- **鱼与熊掌兼得**:保留 native-per-platform(最佳性能/手感/平台规范),又不放任跨端漂移。
- **漂移可见且可执行**:从"靠记性 / 靠跑全套测试"变成"一条命令报表 + 启动即提醒 + 自动 TODO + 逐项动作"。
- **唯一事实是向量(Law 2)**:改了共享契约,落后端的测试**自动变红**,漂移无处可藏——不依赖谁记得。
- **诚实的边界**:报表读的是 `PARITY.md` 的**人工声明**,不替代各端**真实跑向量**(CI 才是终极真值);
  UI 这类无向量项靠交互规格 + 人工走查。工具会显著标注 `DECLARED-ALIGNED ≠ 测试已过`。
- **可增量、跨 agent**:新增平台/功能,只需加向量 + 在 `PARITY.md` 列一行,报表与自动浮现立即纳入;
  机制同时服务 Claude Code(hook)与读 `AGENTS.md` 的其它 agent(仪式指引)。

---

## 附:命令速查 & 文件地图

| 我想… | 怎么做 |
|---|---|
| 看现在哪端落后 | `python3 scripts/parity-drift.py`(或 `--digest`) |
| 在 CI 里卡住漂移 | `python3 scripts/parity-drift.py --fail-on-drift`(或 `--strict`) |
| 改一个共享行为 | 先改 `/spec` + `conformance/*.json`,再实现到向量绿,更新 `PARITY.md` |
| 对齐落后端 | pull → 跑 runner(变红)→ 按 `docs/PARITY-HANDOFF-*.md` 实现 → PARITY 翻 ✅ → 重跑 parity-drift |
| 关掉/调整自动浮现 | 编辑 `.claude/settings.json` 的 `SessionStart`/`UserPromptSubmit` hook(或 `/hooks`) |

机制相关文件:`CONSTITUTION.md` · `PARITY.md` · `conformance/` · `spec/backends.json` · `strings/` ·
`scripts/parity-drift.py` · `.claude/settings.json` · `CLAUDE.md`/`AGENTS.md`(会话启动仪式) ·
`docs/PARITY-HANDOFF-*.md`。
