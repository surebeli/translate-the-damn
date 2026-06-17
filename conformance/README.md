# conformance/ — language-neutral golden vectors

These JSON files define **expected behaviour of the pure logic**, independent of language or
platform. Every platform writes a thin test runner that feeds each case through its **native**
implementation and asserts the result. Same vectors → byte-identical behaviour, without sharing
code (Constitution Law 2).

**Changing a behaviour means changing the vector here first** — which turns every platform's CI red
until it matches. That is the forcing function that prevents drift.

## Format

```jsonc
{
  "fn": "PromptBuilder.Build",      // logical function under test
  "cases": [
    { "name": "...", "in": { ... }, "out": <expected> }
  ]
}
```

`out` may be a scalar (string/number/bool) or an object of expected fields. For object outputs a
runner asserts each present field (extra native fields are ignored), so vectors can assert a subset.

## Vectors

| file | function | notes |
|---|---|---|
| `prompt-builder.json` | substitute source text into the prompt template | `out` = exact string |
| `ansi-stripper.json`  | strip ANSI escapes + CR from CLI output | `in.s` uses `` for ESC |
| `hotkey-parser.json`  | parse "Ctrl+Alt+T" → modifiers + virtual key | `out` asserts a subset of fields |

TODO vectors (logic shipped on Windows, not yet extracted): last-translation cache, config
bootstrap/round-trip, google-v2 / doubao request-body building (drive from `spec/backends.json`).

## Runners

- **Windows (C#)**: `tests/TranslateTheDamn.Tests/Conformance.cs`, run by `dotnet run --project tests/...`
  (the harness walks up to find this `conformance/` dir). This is the reference runner.
- **macOS (Swift)** / **Linux**: add a runner that loads the same JSON and asserts via the native
  impl; wire it into that platform's CI.
