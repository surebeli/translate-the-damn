# Security Policy

## Supported versions

translate-the-damn is pre-1.0; only the **latest released `0.MINOR`** receives security fixes. The
current release is **0.2.0**. Older `0.MINOR` lines are not patched — please upgrade.

| Version | Supported |
|---|---|
| 0.2.x (latest) | ✅ |
| < 0.2.0 | ❌ |

## Reporting a vulnerability

**Please do not open a public issue for security problems.** Report privately, one of:

1. **Preferred** — GitHub Security Advisories: open a private report at
   <https://github.com/surebeli/translate-the-damn/security/advisories/new>.
2. **Email** — surebeli@gmail.com.

Please include: the affected platform (Windows / macOS) and version, the affected component (e.g. a
specific backend, the clipboard watcher, the CLI spawner, config handling), reproduction steps, and
the impact you observed.

**Never include real API keys, tokens, or other live credentials in a report.** Redact them — see
*Handling secrets* below.

### What to expect

This is a small project, so timelines are best-effort:

- Acknowledgement of your report, typically within a few days.
- An initial assessment and, where applicable, a fix or mitigation, coordinated with you.
- Credit in the release notes / advisory if you'd like it.

We ask for **coordinated disclosure**: please give us a reasonable window (around 90 days, sooner if
a fix ships earlier) before any public disclosure.

## Threat model & scope

translate-the-damn is a local desktop tool. Some properties are relevant to security reports:

- **It spawns the user's agent CLIs** (`claude`, `codex`, `copilot`, `agy`, `opencode`, `kimi`,
  `mimo`). On macOS the app is **deliberately not sandboxed** so it can do this — that is by design,
  not a vulnerability. CLIs are spawned from a neutral directory with the prompt passed via stdin
  (to avoid shell-quoting issues); reports about command/argument injection into the spawn path are
  in scope.
- **It makes outbound HTTP requests** to translation / LLM APIs (`google-v2`, `doubao`,
  `deepseek-http`, `mimo-http`, `kimi-http`, and any user-added custom OpenAI/Anthropic provider)
  using a user-supplied key. Reports about how requests are constructed, where keys are sent, or TLS
  handling are in scope.
- **It reads the clipboard.** Reports about unexpected exfiltration of clipboard contents are in
  scope.

### Handling secrets

Secrets live **only** in the local `config.json` (`~/.translatethedamn/config.json`, or
`%USERPROFILE%\.translatethedamn\config.json` on Windows). The `apiKey` field is never committed to
the repository, never logged in plaintext intentionally, and the API Key field in Settings is masked
on both platforms. If you find a path where a secret is written to logs, telemetry, an error popup,
or any committed artifact, **that is a security issue** — report it privately. When you do, redact
the key itself.

## Out of scope

- Vulnerabilities in the third-party CLIs or remote APIs themselves (report those to their
  maintainers).
- The macOS app being un-sandboxed — this is a documented, intentional requirement.
- Issues that require an attacker to already have full local control of the user's machine/account.
