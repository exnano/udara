# Build, notarize, and distribute

## Required configuration

The development bundle ID (`local.udara.udara`) is a local-only placeholder. Before the first release choose a permanent reverse-domain ID under your control; changing it later changes the sandbox container and migration needs.

Supply these environment values outside source control:

| Variable | Purpose |
| --- | --- |
| `UDARA_BUNDLE_ID` | Permanent production bundle identifier |
| `APPLE_TEAM_ID` | Ten-character Apple Developer team ID |
| `SIGNING_IDENTITY` | Full `Developer ID Application: …` identity in Keychain |
| `NOTARY_PROFILE` | Keychain credential profile for `notarytool` |
| `RELEASE_VERSION` | SemVer, e.g. `1.0.0` |
| `BUILD_NUMBER` | Increasing positive integer |
| `GITHUB_REPOSITORY` | Actual `owner/repository` |

Apple Developer Program membership and a valid Developer ID Application certificate are required. Configure notarization credentials using `xcrun notarytool store-credentials` interactively; do not place passwords/private keys in shell scripts, Git, release notes, or logs.

## Local release

1. Run tests, verify previews, and commit the intended source. Create the matching `v<version>` tag; push the tag to the actual GitHub repository before creating the GitHub release.
2. Select Xcode 27.0 using `DEVELOPER_DIR` if needed.
3. Export the settings above, then run `./scripts/release.sh`.
4. Inspect the retained notarization logs and final DMG in `build/releases/<version>/`.
5. Test a browser-downloaded/quarantined build on a clean Mac, including an offline first launch. Test both macOS 26 and 27 and both CPU architectures before claiming that support matrix is verified.
6. Set `RELEASE_NOTES_FILE` to a reviewed Markdown file; run `./scripts/create-draft-release.sh`.
7. Publish the draft only after installation acceptance. The release script does not publish it automatically.

The script builds/tests, archives a universal Release app, exports Developer ID signing, verifies both architectures, submits an app ZIP, checks the notary log, staples the app, builds/signs/notarizes/staples a DMG, mounts it read-only, verifies the enclosed app, and computes SHA-256 last. An existing artifact directory causes an explicit failure rather than overwriting a release. Never replace published versioned assets; issue a new version.

Signature verification uses `codesign --verify`, `spctl --assess`, and `xcrun stapler validate`. Gatekeeper assessment is not a substitute for an actual fresh installation test. The double notarization sequence deliberately staples the app before placing it inside the DMG.

## GitHub Actions

`ci.yml` runs core and Xcode tests plus a universal build without distribution credentials. `release.yml` is manually dispatched against an existing version tag and produces a signed candidate artifact; it does not publish a GitHub release or change a tap.

Both workflows require a runner with `/Applications/Xcode_27.0.app`; they fail rather than silently using a different compiler. They are configured for `macos-26`. Confirm that the hosted runner image includes this newly released Xcode before enabling CI, or assign an equivalent maintained macOS runner with that installation.

Create a protected `release` environment with variables `UDARA_BUNDLE_ID`, `APPLE_TEAM_ID`, and `SIGNING_IDENTITY`. Add secrets:

- `CERTIFICATE_BASE64`: base64-encoded Developer ID `.p12`.
- `CERTIFICATE_PASSWORD`: password for that export.
- `NOTARY_KEY_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`: App Store Connect API key credentials permitted to notarize.

Signing material is imported into a temporary keychain. Cleanup restores the original keychain list/default and deletes the temporary keychain and private files even when the job fails. Do not run this workflow with signing secrets on untrusted pull-request code. Environment rules should restrict release execution to trusted maintainers/tags.

## Homebrew

Create an owned `homebrew-tap` GitHub repository. After publishing the stable GitHub release:

```sh
# Set RELEASE_VERSION, GITHUB_REPOSITORY, and UDARA_BUNDLE_ID first.
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
