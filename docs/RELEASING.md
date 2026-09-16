# Build, notarize, and distribute

## Required configuration

The project code name is **Exnano Udara**. The installed application is **Udara.app**, with display name **Udara** and production bundle identifier **`io.exnano.udara`**. Set `UDARA_BUNDLE_ID=io.exnano.udara` for distribution builds. The development bundle ID (`local.udara.udara`) remains separate. Changing the production identifier later changes the sandbox container and migration needs.

Version/build come from `Config/Version.xcconfig`; see [VERSIONING.md](VERSIONING.md) for bump commands and changelog/tag steps. Supply these identity settings outside source control:

| Variable | Purpose |
| --- | --- |
| `UDARA_BUNDLE_ID` | Permanent production bundle identifier |
| `APPLE_TEAM_ID` | Ten-character Apple Developer team ID |
| `SIGNING_IDENTITY` | Full `Developer ID Application: …` identity in Keychain |
| `NOTARY_PROFILE` | Keychain credential profile for `notarytool` |
| `GITHUB_REPOSITORY` | Actual `owner/repository` |

Apple Developer Program membership and a valid Developer ID Application certificate are required. Configure notarization credentials using `xcrun notarytool store-credentials` interactively; do not place passwords/private keys in shell scripts, Git, release notes, or logs.

## Local .env configuration

The release, draft-release and cask-generation scripts automatically load the repository-root `.env`, regardless of your working directory. `.env` is ignored by Git; `.env.example` is safe to commit.

```sh
cp .env.example .env  # first-time setup only; preserve an existing local file
```

Set your local values:

```dotenv
GITHUB_REPOSITORY=exnano/udara
UDARA_BUNDLE_ID=io.exnano.udara
APPLE_TEAM_ID=6G94876K55
SIGNING_IDENTITY='Developer ID Application: MZR Global Sdn Bhd (6G94876K55)'
NOTARY_PROFILE=udara-notary
```

Then run `./scripts/release.sh` without exporting those variables. Existing exported variables (including empty ones) take precedence, so CI settings remain authoritative. Missing `.env` files are allowed; required release checks still apply. For draft creation, also set `RELEASE_NOTES_FILE` in `.env` or your shell.

The format supports `KEY=value`, optional `export`, single/double quotes, blank lines and comments. Quote values containing spaces. Values are literal: no shell commands, variable expansion, escape-sequence expansion or multiline values. Parse errors report a line number without printing its contents. Notarization credentials stay in Keychain; `.env` only needs the profile name.

## Local release

1. Update the version and changelog using the versioning guide, run tests, verify previews, and commit the intended source. Create the matching `v<version>` tag; push the tag to the actual GitHub repository before creating the GitHub release.
2. Select Xcode 27.0 using `DEVELOPER_DIR` if needed.
3. Configure `.env` (or export the settings above), then run `./scripts/release.sh`.
4. Inspect the retained notarization logs and final DMG in `build/releases/<version>/`.
5. Test a browser-downloaded/quarantined build on a clean Mac, including an offline first launch. Test both macOS 26 and 27 and both CPU architectures before claiming that support matrix is verified.
6. Set `RELEASE_NOTES_FILE` to a reviewed Markdown file; run `./scripts/create-draft-release.sh`.
7. Publish the draft only after installation acceptance. The release script does not publish it automatically.

The script builds/tests, archives a universal Release app, exports Developer ID signing, verifies both architectures, submits an app ZIP, checks the notary log, staples the app, builds/signs/notarizes/staples a DMG, mounts it read-only, verifies the enclosed app, and computes SHA-256 last. An existing artifact directory causes an explicit failure rather than overwriting a release. Never replace published versioned assets; issue a new version.

Signature verification uses `codesign --verify`, `spctl --assess`, and `xcrun stapler validate`. Gatekeeper assessment is not a substitute for an actual fresh installation test. The double notarization sequence deliberately staples the app before placing it inside the DMG.

## GitHub Actions

`ci.yml` runs core and Xcode tests plus a universal build without distribution credentials. `release.yml` takes the version of an existing tag, validates it against the checked-out config, and derives the build number from that config. It is manually dispatched against that tag and produces a signed candidate artifact; it does not publish a GitHub release or change a tap.

Both workflows require a runner with `/Applications/Xcode_27.0.app`; they fail rather than silently using a different compiler. They are configured for `macos-26`. Confirm that the hosted runner image includes this newly released Xcode before enabling CI, or assign an equivalent maintained macOS runner with that installation.

Create a protected `release` environment with variables `UDARA_BUNDLE_ID`, `APPLE_TEAM_ID`, and `SIGNING_IDENTITY`. Add secrets:

- `CERTIFICATE_BASE64`: base64-encoded Developer ID `.p12`.
- `CERTIFICATE_PASSWORD`: password for that export.
- `NOTARY_KEY_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`: App Store Connect API key credentials permitted to notarize.

Signing material is imported into a temporary keychain. Cleanup restores the original keychain list/default and deletes the temporary keychain and private files even when the job fails. Do not run this workflow with signing secrets on untrusted pull-request code. Environment rules should restrict release execution to trusted maintainers/tags.

## Homebrew

Create an owned `homebrew-tap` GitHub repository. After publishing the stable GitHub release:

```sh
# Check out the published version tag; set GITHUB_REPOSITORY and UDARA_BUNDLE_ID.
./scripts/generate-cask.py > /path/to/homebrew-tap/Casks/udara.rb
brew style /path/to/homebrew-tap/Casks/udara.rb
brew audit --cask --online /path/to/homebrew-tap/Casks/udara.rb
```

The generator downloads the public release assets through `gh`, rejects private repositories and drafts/prereleases, and verifies the DMG checksum before producing the cask. Check and commit the resulting cask in the tap. Installation is then `brew install --cask <owner>/tap/udara`; upgrades use `brew upgrade --cask udara`.

Test install, upgrade, ordinary uninstall, and explicit `brew uninstall --cask --zap udara`. Ordinary uninstall preserves preferences; `zap` deletes them. The cask intentionally does not declare `auto_updates`, because v1 has no in-app updater. An official Homebrew/core submission is not required for an owned tap.

## Sources

- [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
- [Open-Meteo usage terms](https://open-meteo.com/en/pricing)
