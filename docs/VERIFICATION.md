# Verification — 16 September 2026

## Confirmed locally

Environment: macOS 27.0 (26A428), Apple silicon, Xcode 27.0 (27A266a), Swift 6.4. No distribution credentials used.

| Check | Result |
| --- | --- |
| `swift test` | 24 tests passed in 6 suites |
| Native Xcode Debug build | Passed |
| Xcode scheme test on macOS | 24 Swift Testing tests and 2 XCTest UI tests passed |
| Release build | Passed |
| `lipo -archs` on final Release executable | `x86_64 arm64` |
| `codesign --verify --deep --strict` on local Release app | Passed, development ad-hoc signature only |
| Release tooling Python tests | 5 passed: public artifact, draft/private rejection, checksum mismatch, repository validation |
| Shell syntax, project/entitlement plist, workflow YAML | Passed |
| Missing-release-configuration preflight | Refused release with `Missing required release setting: UDARA_BUNDLE_ID` |
| Live keyless provider smoke | Kuala Lumpur geocoding plus 72 hourly samples; current-hour sample available |
| Read-only implementation review | No high-impact blockers reported |

Latest Xcode result bundle: `build/VerifiedTests.xcresult` (ignored build artifact).

## Render inspection

The UI tests exercise empty onboarding, fixture city search/addition, return to city list, settings navigation, and screenshot capture in light/dark appearances. Preview fixtures use an injected fixed clock and in-memory data. Screenshot capture is scoped to the Udara window.

- [Light appearance](previews/light.png)
- [Dark appearance](previews/dark.png)

Inspected category badges, row order, long city names, forecast timestamps, fixed-clock download age, scrolling, and footer. The Xcode `#Preview` declarations compile; the same SwiftUI view is rendered by the Debug preview host. A manual Xcode Canvas session and a full VoiceOver audit were not performed.

An initial UI-runner library-validation error was corrected by disabling Hardened Runtime on the test targets only. One UI navigation run lost active-app focus; explicit application activation was added, and the following complete runs passed. The host Xcode installation reports stale CoreSimulator/CoreDevice plug-in warnings; macOS builds and the final tests nevertheless pass.

A test reproduced adding a city during an already-running refresh. The store now schedules a follow-up due check, and the regression test passes.

## External acceptance still required

- Actual Developer ID signing, Apple notarization submission/stapling, and production Gatekeeper assessment.
- Clean-machine installation from a quarantined GitHub download, including offline launch.
- Runtime tests on macOS 26 and Intel hardware. Universal compilation is confirmed, not equivalent to Intel runtime testing.
- Public GitHub repository/release and owned Homebrew tap installation, upgrade, ordinary uninstall and explicit zap.
- Execution of GitHub Actions on the configured runner image; it must have Xcode 27.0 installed at the documented path.

See [RELEASING.md](RELEASING.md) for exact prerequisites and commands. At the initial implementation checkpoint, no app or release had been published, notarized, or uploaded. See the subsequent local-installation result below.

## Versioning update

- Shared `Config/Version.xcconfig` retains the initial `1.0.0 (1)` baseline.
- All app/unit/UI targets resolve those shared settings in Xcode.
- Debug and universal Release builds passed; both generated app Info.plists were checked against the source config.
- 13 release-tooling tests passed, covering version bumps, component resets, monotonically increasing builds, dry runs, invalid/duplicate settings, release mismatches, artifact mismatches, and Homebrew release checks.
- Shell syntax, Xcode project plist, workflow YAML, and `git diff --check` passed.
- No tag, signed release, or publication was created as part of this change. Existing core/UI tests were not rerun for this tooling and version-label update.


## Notarized local installation

Udara **1.0.0 (1)**, bundle ID **io.exnano.udara**, was built as a universal arm64/x86_64 app and signed with Developer ID Application for MZR Global Sdn Bhd (team 6G94876K55).

- Apple notarization submission `1e0fa5ca-9dc9-451d-a57c-c79373e42027`: **Accepted**, no reported issues.
- Ticket stapled to the app and validated successfully.
- Installed at `/Applications/Udara.app` and launched.
- The installed copy passed strict signature verification, stapler validation, version validation, and Gatekeeper assessment: **Notarized Developer ID**.
- Build and notary evidence retained locally in `build/local-install-io/` (ignored artifacts). Credentials remain in Keychain profile `udara-notary`.

This verifies the app installation on this Mac. A notarized DMG, public GitHub/Homebrew distribution, clean-machine offline launch, macOS 26 runtime and Intel hardware runtime tests remain separate outstanding acceptance steps.


## Hourly refresh and Liquid Glass — 1.1.0 (2)

- Forecast downloads become eligible after 3,600 seconds, with 0–60 seconds of jitter and the existing once-per-minute scheduler. Opening the dropdown still makes no request.
- Migrated legacy daily deadlines in memory on load, preserving city selections, cached payloads and persisted server retry deadlines; subsequent saves retain the normalized schedule.
- `swift test` and the native Xcode suite each passed all 26 core tests across 7 suites. Added regression coverage for the hourly boundary and migration with Retry-After preservation.
- All 13 release-tooling tests and both XCTest UI workflows passed. UI navigation verifies the hourly setting.
- Inspected native Liquid Glass rendering in [light](previews/light.png), [dark](previews/dark.png), and [reduced-transparency](previews/reduced-transparency.png) fixtures. AQI badges retain solid fills; reduced-transparency uses bordered controls and an opaque background.
- The accessibility preview override exercises the same fallback branches without changing the user's macOS accessibility preferences.
- Result bundle: `build/HourlyGlassTests.xcresult`; screenshots captured only the preview window. Native Debug tests and universal Developer ID Release archive/export succeeded on macOS 27.
- macOS 26 and Intel runtime verification remain outstanding.

The updated **1.1.0 (2)** app was notarized under submission `65571018-bd4a-44e8-8aa5-6c20495d600f`: **Accepted**, with no issues. The ticket was stapled and validated. Installed `/Applications/Udara.app` passed version validation, strict signature verification, stapler validation, and Gatekeeper assessment (**Notarized Developer ID**), then launched successfully. Previous version retained at `build/local-install-1.1.0/previous/Udara.app`; saved app data was not replaced. Archive, export, and notary evidence are in `build/local-install-1.1.0/`. No public release or DMG was published.


## Current location — 1.2.0 (3)

- Permanent non-removable Current location section sits above the independently sorted saved cities; it remains visible before permission, while locating, when access is denied, and when detection fails.
- Added one-shot Core Location detection and macOS 26 MapKit reverse geocoding. Detected coordinates are rounded to two decimal places before external requests. No continuous tracking or location history.
- App launch, hourly timers, wake and clock changes check location only with authorization. Initial access requires the user to select Enable location and grant macOS permission.
- Both SwiftPM and native Xcode passed 31 core tests in 8 suites; 13 tooling tests and both UI workflows passed. New coverage includes separate location identity, cache reuse/movement, old snapshot compatibility, relaunch gating, temporary-failure cache retention, retry preservation and revocation during an in-flight request.
- UI checks verify the pinned row appears above higher-AQI saved cities and exposes no removal action. Light/dark, reduced-transparency, [denied](previews/location-denied.png), and [unavailable](previews/location-unavailable.png) fixture screenshots were captured. Light/dark and denied screenshots were visually inspected.
- An initial run failed inside XCTest screenshot creation. The subsequent full suite completed successfully with all five window-only captures. Result: `build/LocationVerifiedTests.xcresult`.
- Real permission grant/location detection still requires user interaction and has not been claimed as verified. Automated tests never request or grant real location access.

Universal **1.2.0 (3)** was signed for `io.exnano.udara` with Developer ID team `6G94876K55`. Apple submission `5d78f7f7-7d43-415f-9294-1cc78e398de7` was **Accepted**, without issues. The installed `/Applications/Udara.app` passed strict signature verification, stapler validation and Gatekeeper (**Notarized Developer ID**) and launched successfully. Signed location entitlement and usage descriptions were verified in the exported artifact. The previous app is retained in `build/local-install-1.2.0/previous/Udara.app`; saved-city data was preserved. No GitHub release or DMG was published.


## Menu bar AQI and icon preference — 1.3.0 (4)

- Menu bar renders the icon and AQI together as a template image; it cannot collapse to an icon-only SwiftUI label. Highest available AQI includes current location and saved cities; no reading shows a dash.
- Settings switches between the Udara wind icon and dynamic category icons; the selected mode persists in the existing atomic snapshot. Legacy snapshots default to Udara. Preferences remain isolated in previews/tests.
- 33 core tests passed in 9 suites in SwiftPM and Xcode; all 13 release-tooling tests and the existing 2 UI workflows passed (`build/MenuBarTests.xcresult`).
- The additional menu bar UI workflow passed in `build/MenuBarFinalTests.xcresult`: selected both radio controls, verified the actual status item width, and captured its pixels. Inspected [Udara icon with AQI](previews/menubar-udara.png) and [dynamic icon with AQI](previews/menubar-dynamic.png).
- Initial additional-test failures exposed test locator/type assumptions (StatusItem versus MenuBarItem; NSNumber versus String) and an activation-related missed click. Test queries now match the actual macOS accessibility types, with reactivation when the first Settings click leaves the city page visible.
- Universal Developer ID build passed. Apple submission `1c7eedaf-dc2b-42da-99cc-c622d60bac4b` was Accepted with no issues; the ticket was stapled.
- Installed `/Applications/Udara.app` version 1.3.0 (4), bundle `io.exnano.udara`, passed signature, version, staple, and Gatekeeper checks and launched. Previous app retained in `build/local-install-1.3.0/previous/Udara.app`; app data preserved. No public release was published.


## GitHub source publication validation

The complete local suite passed before publishing to `exnano/udara`: 33 core tests across 9 suites, 20 release-tooling tests and 3 XCTest UI workflows. Result bundle: `build/PublishTests.xcresult`. Staged files were checked for excluded `.env`, generated build artifacts, signing-key files and recognizable credential patterns; `git diff --cached --check` passed. Public DMG and Homebrew publication remain separate from source publication.


## Public GitHub and Homebrew release — 1.3.1 (5)

- Published stable release: https://github.com/exnano/udara/releases/tag/v1.3.1
- Published tap: https://github.com/exnano/homebrew-tap (`Casks/udara.rb`, commit `b565dc5`).
- Build source tag `v1.3.1` points to `f4e09ce`. The earlier `v1.3.0` tag was retained without published assets; the multi-architecture `lipo -verify_arch` call failed, so release tooling now checks each architecture individually.
- Local Xcode 27 release pipeline passed 33 core tests, 20 release-tooling tests and 3 UI workflows, archived/exported the universal Developer ID app, and verified Hardened Runtime and entitlements.
- App notarization `610a78b2-6671-4bb2-af4f-c124bed67e14`: Accepted, no issues.
- DMG notarization `631b4eef-56ee-40a7-b1a4-1471f9ede802`: Accepted, no issues.
- App and DMG stapled and validated; signatures and Gatekeeper passed, including the app mounted from the final DMG.
- Final/public DMG SHA-256: `40b8ee58b646e78e659b1d290182ac85d7c9c2eddd61ea4a6ac37518bccd47bb`. Anonymous GitHub download matched; published assets include `SHA256SUMS`.
- Homebrew style and online audit passed. Updated cask generator to current minimum-macOS syntax and alphabetical zap paths; all 20 tooling tests passed afterward.
- `brew install --cask exnano/tap/udara` installed the public 1.3.1 app into `/Applications`. Installed version, strict signature, staple and Gatekeeper checks passed, and the app launched. Previous manually installed app retained in `build/releases/1.3.1/previous/Udara.app`; user data preserved.
- GitHub-hosted CI currently fails at toolchain selection because its macOS runner lacks `/Applications/Xcode_27.0.app`. This release was built and tested locally; no hosted-CI pass is claimed.
- Clean-machine browser/offline launch, macOS 26 and Intel runtime verification, and Homebrew cross-version upgrade/uninstall acceptance remain outstanding. The install here was on the development Mac.
