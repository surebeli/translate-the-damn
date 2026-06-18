# ISSUE: hopper-dispatch on PATH 指向过期 v0.6.1 安装(mimo 等 vendor 不可用)

> 报告方: translate-the-damn macOS 移植 CEO/CTO 编排(main session)
> 日期: 2026-06-18
> 严重度: 高(阻塞 mimo vendor 派发;hopper 技能默认走 PATH 二进制)
> 状态: 待用户确认修复方式 / 待 hopper 自查

## 现象

`which hopper-dispatch` → `~/.local/bin/hopper-dispatch`,这是一个 3 行 shim:

```sh
#!/bin/sh
exec node "$HOME/.local/share/hopper-plugin/cli/bin/hopper-dispatch" "$@"
```

它指向 `~/.local/share/hopper-plugin/`(独立旧安装,**v0.6.1-phase-6c**)。该版本:

```
$ hopper-dispatch --capabilities mimo
Error: unknown vendor 'mimo'. Known: codex, kimi, opencode, copilot, agy, grok
```

而 Claude Code 插件(0.12.0)自带的 dispatcher
`~/.claude/plugins/marketplaces/agent-hopper/cli/bin/hopper-dispatch` 是 **v0.12.0**:

```
$ node …/agent-hopper/cli/bin/hopper-dispatch --check mimo
| mimo | ~/.nvm/versions/node/v22.22.3/bin/mimo | OK | READY |
```

## 影响

- hopper 技能(`/hopper:dispatch` 等)与裸 `hopper-dispatch` 调用都解析到过期 v0.6.1
  → **mimo vendor 无法派发**,与插件 0.12.0 的 skill 描述(列出 mimo)/ 文档不一致。
- 同机存在两份 hopper 安装(`~/.local/share` v0.6.1 + 插件 0.12.0),版本漂移,易踩坑。
- 本次 translate-the-damn macOS 移植需要 mimo vendor,直接被此问题卡住。

## 定位

| 位置 | 版本 | mimo |
|---|---|---|
| `~/.local/bin/hopper-dispatch` → `~/.local/share/hopper-plugin/...` | 0.6.1-phase-6c | ❌ unknown vendor |
| `~/.claude/plugins/marketplaces/agent-hopper/cli/bin/hopper-dispatch` | 0.12.0 | ✅ READY |

`~/.local/share/hopper-plugin` 是实体目录(非 symlink),日期 2026-06-03,落后于插件。

## 建议修复方向

1. **首选(最小可逆)**:把 `~/.local/bin/hopper-dispatch` shim 重指到 0.12.0 插件二进制
   (`exec node "$HOME/.claude/plugins/marketplaces/agent-hopper/cli/bin/hopper-dispatch" "$@"`),
   让 PATH / 技能统一走 0.12.0。
2. 或:把 `~/.local/share/hopper-plugin` 刷新/重装到 0.12.0,消除双安装。
3. 或(治本):hopper 安装器在更新插件时应同步刷新 `~/.local/share` 副本 + 校验 PATH shim
   版本,并在版本漂移时告警,避免再次发生。

## 备注

本 issue 在 translate-the-damn macOS 移植编排启动时发现(编排需要 mimo vendor)。
workaround:本会话内用绝对路径调用 0.12.0 二进制。待用户确认修复方式后落地。
