# Releasing

Artifacts are published by **`.github/workflows/release.yml`** when you push a version tag.

## Versioning rules (Constitution)

- The git **tag IS the release**: `vMAJOR.MINOR.PATCH` (e.g. `v0.2.0`; pre-releases like
  `v0.3.0-rc1` are marked pre-release automatically).
- The tag must equal the **app version** — macOS `CFBundleShortVersionString` (Resources/Info.plist)
  **and** Windows `<Version>` (App `.csproj`). The release job **fails** if a built artifact's
  version doesn't match the tag, so bump both first.
- Same `MAJOR.MINOR` = same feature set on every platform (Law 3, tracked in `PARITY.md`). The
  `config.json` schema `version` is **independent** of the app version (Law 4) — only bump it on an
  incompatible config-format change.

## Cut a release

1. Bump the version in `platforms/macos/Resources/Info.plist` (`CFBundleShortVersionString`) and
   `platforms/windows/src/TranslateTheDamn.App/*.csproj` (`<Version>`). Commit.
2. Tag the commit that contains `release.yml` and the version bump, then push the tag:
   ```bash
   git tag v0.3.0 && git push origin v0.3.0
   ```
3. The workflow builds on `windows-latest` (the .NET 9 exe → zipped publish folder) and `macos-15`
   (`build-app.sh` → `TranslateTheDamn.app` → zip), verifies the version matches the tag, and creates
   a **GitHub Release** with both archives attached.

`workflow_dispatch` (the "Run workflow" button) runs a **build-only dry run** — it produces the
artifacts but does **not** publish a release.

## ⚠️ The existing `v0.2.0` tag

A `v0.2.0` tag already exists on a commit that **predates** `release.yml`, so it will **not** trigger
this workflow. To actually ship 0.2.0, move the tag onto a commit that contains `release.yml`:

```bash
git tag -d v0.2.0 && git push origin :refs/tags/v0.2.0   # delete old (local + remote)
git tag v0.2.0 <commit-with-release.yml> && git push origin v0.2.0
```

…or simply cut the next version (`v0.3.0`) from current `main`.

## macOS artifact is unsigned

CI does **not** sign or notarize (no secrets in the workflow). Gatekeeper will quarantine the
downloaded `.app`. Tell users to either right-click → **Open** once, or clear the quarantine flag on
the path they unzipped to (not necessarily `/Applications`):

```bash
xattr -dr com.apple.quarantine /path/to/TranslateTheDamn.app
```

For a signed/notarized distribution build, run `platforms/macos/scripts/sign-notarize.sh` locally
with your Developer ID (out of CI scope).
