# Updating Udara's version

`Config/Version.xcconfig` is the single source for every Xcode target in Debug and Release:

```xcconfig
MARKETING_VERSION = 1.0.0
CURRENT_PROJECT_VERSION = 1
```

The first value is the user-facing app version; the second identifies the build. Settings displays both as `Udara 1.0.0 (1)`. Release tags and DMG filenames use the app version. The build number always increases, including across minor/major changes.

`Package.swift`'s `// swift-tools-version: 6.0` declares the SwiftPM tools/language compatibility requirement. **Do not change it when releasing app fixes or features.** It is unrelated to Udara's app version.

## Choose the bump

Use stable `MAJOR.MINOR.PATCH` versions. For this desktop app, compatibility includes existing user workflows, saved-city data, and supported macOS versions.

| Completed change | Command | Example from 1.2.3 (8) |
| --- | --- | --- |
| Bug fix, security fix, or compatible correction | `python3 scripts/version.py bump patch` | 1.2.4 (9) |
| New backward-compatible feature | `python3 scripts/version.py bump minor` | 1.3.0 (9) |
| Breaking workflow/data change or dropping supported macOS versions | `python3 scripts/version.py bump major` | 2.0.0 (9) |
| Internal rebuild of an unpublished candidate, no new user-facing change | `python3 scripts/version.py bump build` | 1.2.3 (9) |

A minor bump resets patch to zero; a major bump resets minor and patch. Every command increments the build by one. Documentation-only changes do not require a bump unless producing a new artifact.

Bump once for each completed fix or feature intended as a separately versioned delivery, not for every editing step or test run. If several changes are grouped into one release, bump once using the highest-impact change: major > minor > patch. Automatic commit-message interpretation is deliberately not used.

These rules follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html), adapted to the desktop app's compatibility promises. The script accepts only stable numeric versions; prerelease suffixes are not implemented.

## Everyday workflow

Run from the repository root:

```sh
# Check current app version, build, and proposed tag.
python3 scripts/version.py show

# Preview without changing any files.
python3 scripts/version.py bump patch --dry-run

# After completing a bug fix, apply the bump.
python3 scripts/version.py bump patch

# For a feature, choose minor INSTEAD of patch.
# python3 scripts/version.py bump minor

# Add a concise Added/Changed/Fixed entry under Unreleased in CHANGELOG.md.
python3 scripts/version.py check
./scripts/test.sh
./scripts/build.sh Release

git diff -- Config/Version.xcconfig CHANGELOG.md
# Commit the relevant code/tests together with the config and changelog.
```

The bump command updates only the version config, preserving comments and replacing the file atomically. It does not commit, tag, push, build, or publish. Do not manually edit duplicate version values in Xcode's target Build Settings; all targets inherit this config. After a rebase, compare with the target branch and ensure the final version/build is greater than the last published one; version bumps cannot coordinate across independent branches automatically.

## Release workflow

1. Finish the fix/feature, select the appropriate bump, and run the checks above.
2. When cutting the release, replace the changelog's `Unreleased` heading with `X.Y.Z — YYYY-MM-DD` and add a fresh `Unreleased` section above it. Include migration notes for a major release. The initial baseline has not been published; include its features in the first release notes.
3. Commit the release changes. Confirm a clean working tree.
4. Create an immutable annotated tag on that exact commit:

   ```sh
   release_tag="$(python3 scripts/version.py show --field tag)"
   git tag -a "$release_tag" -m "Udara $release_tag"
   # Push the branch and this tag to your configured GitHub remote when ready.
   git push origin "$release_tag"
   ```

5. Follow [RELEASING.md](RELEASING.md) to sign/notarize and create the draft. The scripts derive version/build from the checked-out config. Build and notarize locally, then upload and publish manually; GitHub Actions is not used.
6. Publish only after acceptance, then generate/update the Homebrew cask from the same release checkout.

`RELEASE_VERSION` and `BUILD_NUMBER`, if already present in the environment, are checked as assertions and must match the config. Unset stale values with `unset RELEASE_VERSION BUILD_NUMBER`. They cannot override the source of truth. Build scripts verify the resulting Info.plist, and the signing script verifies the exported app again before notarization.

**Never move a published tag or replace a published DMG.** For a new public artifact, increase at least the patch version even if only packaging changed. Homebrew upgrades by the app version, so a build-only bump cannot deliver a public update through the existing cask strategy. A build-only bump is for local unpublished candidates; create the release tag only once the candidate is finalized. Local release directories are also protected against overwrite—archive a failed attempt before retrying.

## Mapping

| Consumer | Version source |
| --- | --- |
| Xcode app/unit/UI targets | Shared project-level Version.xcconfig |
| App `CFBundleShortVersionString` | `MARKETING_VERSION` |
| App `CFBundleVersion` | `CURRENT_PROJECT_VERSION` |
| Settings display | Built app's Info.plist |
| Git tag | `v<MARKETING_VERSION>` |
| DMG | `Udara-<MARKETING_VERSION>-universal.dmg` |
| Homebrew cask | Config version, verified against public release checksum |

Apple references: [app version](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring), [build version](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion).
