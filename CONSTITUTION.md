# CONSTITUTION — translate-the-damn 多端开发宪法

> 这是仓库的**唯一入口**。任何人 / 任何 AI session 落进这个仓库,**先读本文件**。
> 它只装两样东西:**不可违背的法则(Laws)** 和 **指向一切的指针地图(Map)**。
> 本文件**薄而稳**;它指向的内容(spec / 向量 / 矩阵 / 清单)才是会频繁变的。

各平台原生开发(Windows = C#/WPF,macOS = Swift,Linux = 原生),**不共享 UI/运行时代码**。
统一不靠共享二进制,而靠**共享契约 + 一致性向量 + 治理流程**。本宪法就是那个总闸。

---

## 一、法则(Laws)— 几乎不变

1. **Spec-first**:任何行为/逻辑变更,**先**改 `/spec` 与 `/conformance`(契约和向量),**再**动平台代码。
2. **共享向量是唯一事实**:`/conformance` 的向量必须在**每个平台的 CI 都跑绿**。
   改一端的行为 ⇒ 必须改对应向量 ⇒ 其他平台的 CI **自动变红**。**漂移 = 构建失败,不靠记性。**
3. **同一 `MAJOR.MINOR` = 同一功能集**(见 spec §12 版本规范)。某平台没跟上就停在低版本,
   差异只记在 `PARITY.md`,**绝不让同一版本号在不同平台含义不同**。
4. **config schema 神圣**:`config.json` 的数据格式只有不兼容变更才升 `version` 字段,三端同步。
   它与 App 版本号**相互独立**。
5. **一致性边界**:**必须完全一致** = 功能 / 行为 / 计时 / 状态机 / 文案 / config 格式 / 后端调用;
   **必须各自原生** = 视觉质感(Acrylic vs NSVisualEffectView)/ 系统集成(托盘、热键、剪贴板、权限)/ 控件样式。
   一句话:**"同一套行为,各自原生的皮"**。
6. **后端定义优先做成数据**:后端是变化最频繁的部分。新增/修改后端**先改 `spec/backends.json`**(声明式数据),
   各平台用通用解释器读它;只有清单表达不了的怪逻辑才各端原生 hook,并记进 `PARITY.md`。

---

## 二、指针地图(Map)— 指向会变的内容

| 你要找 | 去这里 |
|---|---|
| 设计与行为规格(单一事实源) | `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md` |
| 声明式后端清单(数据) | `spec/backends.json` |
| 语言中立一致性向量(CI 必跑) | `conformance/`(格式见 `conformance/README.md`) |
| 界面文案 / i18n | `strings/`(如 `strings/zh-CN.json`) |
| 平台对齐矩阵(谁欠什么) | `PARITY.md` |
| 版本规范(App 版本 vs config schema) | design spec **§12** |
| 平台移植指南 | `docs/PORTING-macos.md`、`docs/PORTING-linux.md` |
| 变更检查单(spec-first 落地) | `.github/PULL_REQUEST_TEMPLATE.md` |

---

## 三、平台与目录

- 各平台的本地 `CLAUDE.md` 是"薄指针",内容只一句:遵守本宪法 + 本平台特有注意事项。
- **Windows** 当前位于仓库根的 `src/`(Core + App)与 `tests/`。当 macOS / Linux 加入时,
  约定目录为 `platforms/<os>/`(Windows 可一并迁到 `platforms/windows/`)。
- 共享层(`spec/`、`conformance/`、`strings/`、`PARITY.md`、本宪法)放仓库根,随 git 流转到每个开发环境。

---

## 四、一次变更怎么走(给落进来的人 / agent)

1. 先在共享层落地:改 design spec / `spec/backends.json` / `conformance` 向量 / `strings`。
2. 在你当前平台实现,CI 跑绿;`PARITY.md` 把该功能在本平台标 ✅、其他平台标 ⬜。
3. push。**此刻其他平台 CI 已因向量不匹配而变红**——它们欠的活被自动暴露。
4. 切到另一平台环境、pull → 看 `PARITY.md` 的 ⬜ + 跑红的向量 = 这次要补什么 → 实现到向量跑绿。

> 你照样一次只在一个环境干活。"还欠哪些平台"由**测试和矩阵**盯着,不由你的脑子盯着。
