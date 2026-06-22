# translate-the-damn · 复制即译的原生划词翻译

<b>简体中文</b> · <a href="README.en.md">English</a>

[![conformance](https://github.com/surebeli/translate-the-damn/actions/workflows/conformance.yml/badge.svg)](https://github.com/surebeli/translate-the-damn/actions/workflows/conformance.yml)
[![release](https://github.com/surebeli/translate-the-damn/actions/workflows/release.yml/badge.svg)](https://github.com/surebeli/translate-the-damn/actions/workflows/release.yml)

> **复制任意外语 → 按一个热键 → 当场读到译文。** 一个给 macOS 与 Windows 打造的**原生**沉浸式翻译小工具:
> 不切窗口、不跳应用,尽量不打断你的阅读。它**复用你已经在用的大模型**——API、订阅、命令行 CLI 都行,
> 自带 Key、成本极低,开源免费。

为读一篇英文资料、查一个生僻词,就要切到词典、甚至开一个大模型——ROI 太低了。translate-the-damn 把这件事压成
**「复制 + 一个热键」**:它监听剪贴板(可开关)和一个可配置的全局热键,把文本交给一个**可插拔后端**——你已经
登录的 **Agent CLI**,或一个 **翻译 / 大模型 HTTP API**——再用一个**不抢焦点**的浮窗把译文呈现出来。

<table>
<tr><td align="center"><b>macOS</b></td><td align="center"><b>Windows</b></td></tr>
<tr>
<td width="50%"><img alt="macOS — 译文浮窗" src="docs/assets/popup-result-macos.png" width="100%"></td>
<td width="50%"><img alt="Windows — 译文浮窗" src="docs/assets/popup-result-windows.png" width="100%"></td>
</tr>
</table>

| 平台 | 状态 | 技术栈 |
|---|---|---|
| **Windows 11** | ✅ 已发布 | C# / .NET 9,WPF + WinForms 托盘,Win32 P/Invoke |
| **macOS**(Apple Silicon, 14+) | ✅ 已发布,与 Windows 功能对齐 | Swift,SwiftUI + AppKit,Carbon 热键 |
| **Linux**(Ubuntu 24.04+) | ⬜ 计划中 | 见 `docs/PORTING-linux.md` |

## 为什么是它:四个核心优势

- **🧱 原生开发,各端各做各的。** Windows(WPF/.NET 9)与 macOS(SwiftUI/AppKit,Apple Silicon)是**两套原生
  应用**,不共享 UI / 运行时代码,各自吃透系统能力(非抢焦点浮窗、全局热键、托盘 / 菜单栏、毛玻璃)。一致性
  由**语言无关的一致性向量 + 奇偶矩阵 + CI** 保证,而不是靠塞一个跨平台壳。结果:轻、跟手、像系统自带的一部分。
- **🔌 复用你已有的大模型访问方式 —— 不绑死任何一家。** 同一个声明式清单(`spec/backends.json`)后面挂着三类后端:
  - **Agent CLI**(用你已登录的订阅,无需额外 Key):`claude`、`codex`、`copilot`、`agy`(Google Antigravity,
    回退 `gemini`)、`opencode`、`kimi`、`mimo`。
  - **翻译 / 大模型 HTTP API**(自带 Key):`google-v2`(Google 翻译 v2)、`doubao`(火山方舟),以及一个**通用
    OpenAI / Anthropic 协议 HTTP** 后端,内置 DeepSeek / MiMo / Kimi 预设,填 Key 即用。
  - **自定义服务商**:在设置里把通用 HTTP 后端指向**任意** OpenAI 兼容(`/chat/completions`)或 Anthropic 兼容
    (`/messages`)端点,填 base URL + Key + 协议开关即可,用完还能删。
- **💸 成本极低。** 用你**已经付费**的订阅或额度,或自带一个便宜的 API Key;CLI 路径几乎是「白嫖」你手上的订阅。
  **未来还会支持本地模型**——届时接近零成本、且完全离线。
- **🔒 数据留在本机。** 配置与密钥只写在 `~/.translatethedamn/config.json`(Windows 为
  `%USERPROFILE%\.translatethedamn\config.json`),**永不**提交到仓库、永不上传。

## 功能亮点

- **两种触发,零上下文切换。** 可暂停的剪贴板监听(复制即翻译)+ 一个可配置的全局热键(翻译当前剪贴板)。默认热键:
  macOS `⇧⌘C`、Windows `Shift+Alt+C`;热键冲突会在设置里实时检测并提示。
- **永不抢焦点的浮窗。** 译文出现在屏幕顶部中央的玻璃卡片里(macOS 非激活 `NSPanel` / Windows `WS_EX_NOACTIVATE`),
  你当前的应用**不丢焦点、不吞按键**。原文(斜体)在上、译文(粗体)在下,带**复制译文 / 关闭**;悬停不消失,
  到点自动关闭,还能**拖动卡片**临时换位置。
- **自适应大小 + 历史回看。** 长原文自动用更大的卡片;**◀ ▶** 翻看最近 5 条译文(如 `2 / 3`),无需重新翻译。
- **内置后端体检(doctor)。** 一键 **检测** 跑一次非交互的鉴权 / 连通性探测,点亮状态灯(检测中 / 正常 / 失败),
  在你依赖某个后端前先确认它真的能用。
- **可编辑模型 + 分级推理。** 选或输入模型(支持的后端可**实时拉取 `/models`**)、选目标语言、为暴露该能力的 CLI
  设置推理强度档位。
- **最近翻译缓存。** 最近 5 条成功译文按(文本 + 后端 + 模型)缓存,重复翻译同一段内容**秒回**,不再重复调用模型。
- **明暗 + 本地化 UI。** 设置与浮窗跟随系统外观;界面为简体中文。

## 各种访问方式的耗时(客观数据)

不同的后端是**不同的取舍**,不是「谁更好」。为了让你心里有数、也避免「某种方式是不是很慢」的主观顾虑,下面是在一台
Apple Silicon Mac 上、同一段约 18 词英文、**冷启动管线(无缓存)单次**的实测延迟:

| 访问方式 | 代表后端 | 单次翻译实测 | 说明 |
|---|---|---|---|
| **HTTP API**(自带 Key) | Kimi / MiMo / DeepSeek 预设 | **~1–5 秒** | 直连一次 HTTP 请求,**最快的路**;Kimi 端点可低至 ~1s |
| **自定义 HTTP** | 任意 OpenAI/Anthropic 兼容端点 | **~1–6 秒** | 取决于你指向的服务 |
| **Agent CLI**(轻) | `codex` · `kimi` · `opencode` · `mimo` | **~5–8 秒** | 每次翻译要**冷启动一个 Agent 进程** |
| **Agent CLI**(重) | `claude` · `copilot` | **~10–16 秒** | 重型 Agent(更强推理 / 更多上下文),换来「复用订阅、零额外 Key」 |

一句话:**想要快,就走 HTTP API**(1–5 秒);**想白嫖已有订阅,就走 CLI**——它慢几秒是因为每次都在拉起一个完整的
Agent 进程,这是一个「省钱 vs. 速度」的自觉取舍,不是 bug。命中缓存的重复翻译则是**瞬时**返回。

> 这些后端是按**作者自己手上的资源和使用习惯**配的。想接入别的(比如**微软翻译、阿里云百炼 / 通义**等)?
> **欢迎来提 [issue](https://github.com/surebeli/translate-the-damn/issues)** —— 后端是声明式清单驱动的,加一个并不难。

> 你的配置与密钥只在本机:设置存于 `~/.translatethedamn/config.json`;API Key 只写在该文件里,**永不提交**。

## 安装与运行

### 下载预编译版本

到 [**Releases**](https://github.com/surebeli/translate-the-damn/releases/latest) 页拿最新压缩包:

- **macOS**(Apple Silicon)— `TranslateTheDamn-<version>-macos-arm64.zip`
- **Windows 11**(x64)— `TranslateTheDamn-<version>-windows-x64.zip`

> **⚠️ macOS Gatekeeper** —— macOS 包**未签名 / 未公证**,首次打开会被拦。要么**右键 App → 打开**(确认一次),
> 要么对你解压到的目录清除隔离属性:
> ```bash
> xattr -dr com.apple.quarantine /path/to/TranslateTheDamn.app
> ```
> (不一定是 `/Applications`,用你实际解压的路径。)

### 从源码构建

**macOS**(Apple Silicon,Xcode 16 / Swift 6 命令行工具):

```bash
./platforms/macos/scripts/build-app.sh        # → platforms/macos/TranslateTheDamn.app
open platforms/macos/TranslateTheDamn.app
```

**Windows 11**(.NET 9 Desktop SDK/运行时):

```powershell
dotnet build platforms\windows\TranslateTheDamn.sln -c Release
.\platforms\windows\src\TranslateTheDamn.App\bin\Release\net9.0-windows\TranslateTheDamn.exe
```

**没有主窗口** —— 在菜单栏(macOS)/ 系统托盘(Windows)找图标(绿 = 监听中,灰 = 暂停),点它进设置或退出。
macOS 上 App **刻意不开沙箱**(否则无法拉起你的 CLI);分发用签名 + 公证版请用 `platforms/macos/scripts/sign-notarize.sh`。

## 使用

首次启动会写入 `~/.translatethedamn/config.json`(含合理默认值)。之后,**设置窗口 + 该文件**即真相来源,改了即时热重载,无需重启。

<table>
<tr><td align="center"><b>macOS</b></td><td align="center"><b>Windows</b></td></tr>
<tr>
<td width="50%"><img alt="macOS — 设置(内置 CLI 后端)" src="docs/assets/settings-builtin-macos.png" width="100%"></td>
<td width="50%"><img alt="Windows — 设置(内置 CLI 后端)" src="docs/assets/settings-builtin-windows.png" width="100%"></td>
</tr>
</table>

- **监听与触发** — 开关剪贴板监听、设置**翻译热键**;实时检测它是否可用(✓ 绿)或已被占用。
- **翻译后端** — 选目标语言 + 后端(如 `claude · CLI`),再选 / 输入模型。默认:`claude` / `haiku`。
- **浮窗展示** — 视觉风格(毛玻璃 / 纯色)、自动消失时间、悬停保持不消失。
- **通用** — 开机自启;底部提示配置 + Key 仅存本机。

**翻译:** 复制文本(开了监听就「复制即翻译」),或按热键。后端运行时显示加载动画,随后玻璃卡片滑入而**不抢焦点**——
**复制译文** 拷走、**关闭** 收起、悬停保持;**◀ ▶** 翻看最近 5 条;长原文自动放大。

<table>
<tr><td align="center" colspan="2"><b>翻译中</b></td><td align="center" colspan="2"><b>历史 ◀ ▶</b></td></tr>
<tr><td align="center">macOS</td><td align="center">Windows</td><td align="center">macOS</td><td align="center">Windows</td></tr>
<tr>
<td width="25%"><img alt="macOS — 翻译中" src="docs/assets/popup-loading-macos.png" width="100%"></td>
<td width="25%"><img alt="Windows — 翻译中" src="docs/assets/popup-loading-windows.png" width="100%"></td>
<td width="25%"><img alt="macOS — 历史回看" src="docs/assets/popup-history-macos.png" width="100%"></td>
<td width="25%"><img alt="Windows — 历史回看" src="docs/assets/popup-history-windows.png" width="100%"></td>
</tr>
</table>

后端没登录或断网时,浮窗会用**红色清晰报错**,并把你引回设置里的 doctor:

<table>
<tr><td align="center"><b>macOS</b></td><td align="center"><b>Windows</b></td></tr>
<tr>
<td width="50%"><img alt="macOS — 错误态" src="docs/assets/popup-error-macos.png" width="100%"></td>
<td width="50%"><img alt="Windows — 错误态" src="docs/assets/popup-error-windows.png" width="100%"></td>
</tr>
</table>

用 **检测** doctor 给后端**体检** —— 非交互的鉴权 / 连通性探测 + 状态灯(正常 / 失败):

<table>
<tr><td align="center"><b>macOS</b></td><td align="center"><b>Windows</b></td></tr>
<tr>
<td width="50%"><img alt="macOS — doctor 灯(正常)" src="docs/assets/settings-lamp-ok-macos.png" width="100%"></td>
<td width="50%"><img alt="Windows — doctor 灯(正常)" src="docs/assets/settings-lamp-ok-windows.png" width="100%"></td>
</tr>
</table>

**HTTP API / 自定义服务商:** 选一个 HTTP 后端(`doubao`、`google-v2`,或 DeepSeek/MiMo/Kimi 预设),填遮罩的 API Key +
端点;**检测已有密钥** 可自动发现本机已有的(经同意、仅静态 Key)。接入其它服务就 **新增 provider…**:填 base URL + Key,
选 **OpenAI(`/chat/completions`)** 或 **Anthropic(`/messages`)**:

<table>
<tr><td align="center"><b>macOS</b></td><td align="center"><b>Windows</b></td></tr>
<tr>
<td width="50%"><img alt="macOS — 自定义服务商" src="docs/assets/settings-custom-macos.png" width="100%"></td>
<td width="50%"><img alt="Windows — 自定义服务商" src="docs/assets/settings-custom-windows.png" width="100%"></td>
</tr>
</table>

## 翻译规则

翻译规则内置在 `translation.promptTemplate`:英文原文 ⇒ 专业术语保留英文、其余翻译;非英文原文 ⇒ 全部翻译;代码块 / 命令
保持原样。目标语言通过 `{target}` 占位符统一、在设置里可选;源语言由大模型自动识别。

## 后端说明

- **Agent CLI** 需已安装且**已登录**;它们较重(推理 + 上下文),一次翻译约 5–16 秒——**想快就用 HTTP API**。CLI 从中性沙箱
  目录拉起(不加载你当前项目),提示词走 stdin 以避免 shell 转义问题。
- **`claude` / `codex`** 在 Windows 上有端到端实测;**`google-v2` / `doubao`** 与 HTTP 大模型服务商为请求 / 解析单测——填 Key
  即用;**`copilot` / `agy`** 为尽力而为(需 token / 登录,有已知非交互 CLI 怪癖)。共享的请求 / 解析、缓存、热键、配置、
  推理档位与 doctor 逻辑由一致性向量锁定,在 Windows 与 macOS 的 CI 上**双绿**(向量为离线,实时 CLI/HTTP 调用不在 CI 内跑)。

## 跨平台一致性

本仓库由 **[CONSTITUTION.md](./CONSTITUTION.md)** 统辖(唯一入口 + 指针图)。三条法则:改共享行为**先**改 `/spec` + `/conformance`;
`conformance/` 里的语言无关向量是共享逻辑的唯一真相;同 `MAJOR.MINOR` 即同功能集,记录在 **[PARITY.md](./PARITY.md)**。

这些向量在**每次 push/PR 的 CI** 上、由各平台原生 runner 跑*同一份* JSON——Windows `dotnet run`、macOS `swift test`
(`.github/workflows/conformance.yml`)。流水线还防奇偶漂移:**耦合门**会让「改了 `platforms/<os>/src/**` 却没动 `PARITY.md`」
的 PR 失败;**`parity-verify`** 把各平台真实向量结果与其 PARITY 列交叉核对;**`parity-evidence`** 要求每个 ✅ UI 行都指向真实源码。
后端在 `spec/backends.json` 里声明一次;macOS 通过通用解释器读该清单(宪法第 6 条),Windows 适配器正在重构为同样方式。漂移如何
自动浮现、如何跨端对齐一个功能,见 **[docs/CROSS-PLATFORM-PARITY.md](./docs/CROSS-PLATFORM-PARITY.md)**。

## 开发

```powershell
# Windows — 离线一致性 + 单元套件(无依赖、无网络 / 进程)
dotnet run --project platforms\windows\tests\TranslateTheDamn.Tests
```

```bash
# macOS — 一致性 + 单元套件
( cd platforms/macos && swift test )

# 跨平台漂移报告(Python 标准库,无依赖)
python3 scripts/parity-drift.py
```

Windows 解决方案零外部依赖(仅框架:WPF + WinForms + JSON/HTTP + P/Invoke);macOS 包仅 Foundation/AppKit。两端都把
`Core`(平台无关、向量测试的逻辑)与 `App`(原生 UI)分离。贡献遵循 spec-first 流程,见 **[CONTRIBUTING.md](./CONTRIBUTING.md)**。
设计文档:`docs/superpowers/specs/2026-06-17-translate-the-damn-design.md`。

## 许可

[MIT](./LICENSE) © translate-the-damn contributors
