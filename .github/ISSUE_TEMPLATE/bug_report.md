---
name: Bug report
about: Report a reproducible problem in translate-the-damn
title: "[bug] "
labels: bug
assignees: ''
---

<!--
  Before filing:
  - Is this a SECURITY issue (secret leak, injection, etc.)? Do NOT file it here —
    follow SECURITY.md and report privately.
  - NEVER paste real API keys, tokens, or your config.json contents. Redact them.
-->

## What happened

A clear description of the bug, and what you expected instead.

## Platform & build

- [ ] Windows 11 (C# / .NET 9, WPF)
- [ ] macOS (Apple Silicon, 14+)

- App version (e.g. `0.2.0`):
- OS version:
- How you built/ran it (e.g. `dotnet build ... -c Release`, `./platforms/macos/scripts/build-app.sh`,
  or a downloaded release):

## Backend involved

Which backend was selected when the bug occurred?

- Family: [ ] Agent CLI  [ ] HTTP API  [ ] Custom provider  [ ] N/A
- Backend id (e.g. `claude`, `codex`, `copilot`, `agy`, `opencode`, `kimi`, `mimo`, `google-v2`,
  `doubao`, `deepseek-http`, `mimo-http`, `kimi-http`, or a custom OpenAI/Anthropic provider):
- Model (if applicable):
- For CLI backends: is the CLI installed and logged in? [ ] yes [ ] no [ ] n/a

## Trigger

- [ ] Clipboard watch (复制即翻译)
- [ ] Global hotkey (which combo:                )
- [ ] Settings / doctor / other UI (describe):

## Steps to reproduce

1.
2.
3.

## Logs / screenshots

Paste any relevant error text or a screenshot of the popup/Settings.
**Redact API keys and any other secrets first.**

```
(paste here)
```

## Shared-logic discrepancy? (optional)

If the bug looks like the two platforms behave *differently* for the same input (prompt building,
ANSI stripping, hotkey parsing, request shape, cache, popup sizing, effort tiers, doctor probe,
config defaults, credential discovery), name the relevant `conformance/*.json` vector if you can —
it helps us pin the fix spec-first. See `CONTRIBUTING.md`.

## Additional context

Anything else that might help.
