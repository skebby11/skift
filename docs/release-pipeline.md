# Release pipeline (M5): tagged builds → GitHub Release with .dmg

*Design note, 2026-07-12. See Plan.md §6 (M5) and §8 to-do.*

## Goal

Turn a version tag (`v0.1.0`) into a downloadable, mountable `Skift.dmg`
attached to a GitHub Release, so shipping v0.1 is one `git tag` away once the
remaining M5 items (icon, hardware validation) land. Signing and notarization
are *prepared for* but optional: the pipeline must produce a working artifact
today, without an Apple Developer account.

## Scope

In: a local script that builds Release and packages a .dmg (testable on any
Mac); a GitHub Actions workflow triggered by `v*` tags (plus manual
`workflow_dispatch` for dry runs) that runs the script and uploads the
artifact to a draft Release; ad-hoc code signing; version stamped from the
tag. Out: real Developer ID signing/notarization (steps stubbed behind
secrets that don't exist yet), App Store distribution, auto-update
(Sparkle), changelog generation.

## Architecture

- **`scripts/release.sh`** — single source of truth, runs locally and in CI:
  `xcodegen generate` → `xcodebuild -configuration Release build` (unsigned,
  `CODE_SIGNING_ALLOWED=NO`) → ad-hoc sign the .app (`codesign --force
  --deep -s -`) so Gatekeeper treats it consistently ("right-click → Open"
  path; DECISION: ad-hoc until a Developer ID exists) → `hdiutil` builds a
  compressed UDZO .dmg containing `Skift.app` and an `/Applications`
  symlink. Version: takes `MARKETING_VERSION` from its first argument
  (defaults to `0.0.0-dev`) and passes it to xcodebuild so the bundle
  version matches the tag.
- **`.github/workflows/release.yml`** — on `v*` tag push or manual dispatch:
  macos-15 runner, brew-installs XcodeGen (same as ci.yml), runs the test
  suite first (a release build must never skip tests), then
  `scripts/release.sh "${TAG#v}"`, then creates a **draft** GitHub Release
  with the .dmg attached (`softprops/action-gh-release` or `gh release
  create --draft`). Draft, so a human writes notes and publishes — the
  pipeline never publishes on its own.
- A notarization step is present but no-ops unless `APPLE_ID` /
  `APPLE_TEAM_ID` / `APPLE_APP_PASSWORD` secrets exist (documented inline
  with a REVIEW: enable once a Developer ID account is available).

## Testing

`scripts/release.sh` is exercised end-to-end locally: it must produce a
mountable .dmg whose app launches. The workflow YAML can't run locally;
it is kept trivially thin (checkout, brew, test, script, release) so the
script carries all logic. First real verification: a manual
`workflow_dispatch` run after merge, before the first tag.
