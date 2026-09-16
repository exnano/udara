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

See [RELEASING.md](RELEASING.md) for exact prerequisites and commands. No app or release has been published, notarized, or uploaded.
