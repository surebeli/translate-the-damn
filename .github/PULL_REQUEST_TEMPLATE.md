<!-- Governed by CONSTITUTION.md — spec-first is Law 1. -->

## What changed



## Parity checklist (Constitution)

- [ ] Behavior / logic change? → updated `/spec` and/or `conformance/` vectors **first**
- [ ] New or changed backend? → updated `spec/backends.json` (the shared manifest), not only platform code
- [ ] User-visible text? → updated `strings/`
- [ ] config format change? → bumped the `config.json` `version` field (and noted it)
- [ ] Updated `PARITY.md` (which platforms now owe this feature)
- [ ] Conformance vectors pass on this platform's CI
- [ ] If releasing: bumped the app version per spec §12 (same `MAJOR.MINOR` = same feature set across platforms)

## Platform impact

- [ ] Windows  - [ ] macOS  - [ ] Linux
