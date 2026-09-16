# Exnano Udara: macOS Menu Bar AQI App — Implementation Plan

**Identity:** Project code name Exnano Udara; application Udara.app; display name Udara; production bundle identifier io.exnano.udara.

**Goal:** Native SwiftUI menu bar access to saved cities, sorted by descending estimated US AQI, with hourly local caching and signed GitHub/Homebrew distribution.

**Architecture:** Domain value types → Open-Meteo providers and actor repository → main-actor observable store → SwiftUI scenes. A native Xcode project contains app, Swift Testing unit tests, and XCTest UI tests. The same core sources also run through a dependency-free Swift package test harness.

**Toolchain:** Xcode 27.0, Swift 6.4 compiler / Swift 6 language mode, macOS 26+ app, universal arm64/x86_64 Release builds.

**Accepted revision (16 September 2026):** Hourly downloads replace the original daily policy, with up to 60 seconds of scheduling jitter. Existing deadlines migrate without losing cities or retry limits. Use native SwiftUI Liquid Glass for navigation/actions, solid category badges, and a reduced-transparency fallback. Provider model runs can be less frequent than downloads.

## 1. Project and interface

- [x] Native Xcode project, shared Udara scheme, app/unit/UI test targets.
- [x] MenuBarExtra window style, LSUIElement, 360-point dropdown, scrollable city list capped at 520 points.
- [x] Highest available current AQI in menu label; neutral unavailable state.
- [x] City name/region/country, numeric AQI, category icon/text/colour, forecast hour and download age.
- [x] Descending AQI, city/country/ID tie breaks, unavailable last.
- [x] City search/add/remove, duplicate protection, persistent choices, empty onboarding.
- [x] Native light/dark materials, reduced-transparency adaptation, keyboard-accessible controls and VoiceOver labels.
- [x] Settings/about, source attribution, refresh status and Quit.

| AQI | Category | Colour | Symbol |
| --- | --- | --- | --- |
| 0–50 | Good | Green | leaf.fill |
| 51–100 | Moderate | Yellow | circle.lefthalf.filled |
| 101–150 | Unhealthy for sensitive groups | Orange | exclamationmark.circle.fill |
| 151–200 | Unhealthy | Red | exclamationmark.triangle.fill |
| 201–300 | Very unhealthy | Purple | exclamationmark.octagon.fill |
| 301+ | Hazardous | Maroon | xmark.octagon.fill |

Round once for both display/category. Reject negative, missing, non-finite, and nonrepresentable numbers. Use dark foregrounds on light category badges and white on dark badges.

## 2. Data and persistence

- [x] SavedCity, HourlyAQISample, CityForecast, AQICategory and injectable provider/clock interfaces.
- [x] Open-Meteo keyless geocoding: minimum three characters, 400 ms debounce, cancellation, ten results, normalized search cache for 30 days.
- [x] Forecast request: hourly=us_aqi, forecast_days=3, timezone=GMT, timeformat=unixtime.
- [x] Hourly cache per city; hourly local value selection; exact UTC hour only, never carry forward stale samples.
- [x] No request on dropdown opening; startup/background/wake check due entries without bypassing TTL.
- [x] Maximum two HTTP requests; same-city request deduplication; persisted 0–60-second refresh jitter.
- [x] Retry-After and persisted 1/5/15/60-minute retry ladder with jitter; cancellation excluded from failures.
- [x] Preserve successful cache on errors. Label overdue coverage; unavailable when current-hour sample is absent.
- [x] Atomic versioned disk state, retained city coordinates, bounded search-cache size.
- [x] Preserve corrupt/unsupported state and surface an in-memory-session warning.
- [x] Handle removal during requests, wake, clock changes, and rollback without a request burst.

Use Open-Meteo/CAMS **model estimates**, not IQAir readings. Free non-commercial usage was explicitly chosen. No API credentials, accounts, analytics or backend. Optional location detection was added in the 1.2.0 revision below. Source and licence attribution are mandatory. Large-scale/commercial distribution requires revisiting the service agreement.

## 3. Previews and tests

- [x] Offline fixed-time in-memory previews for category list, light/dark, onboarding, overdue, unavailable, search, settings and row.
- [x] Debug-only preview host window; isolated production storage/network.
- [x] Domain/provider/repository/store tests and UI navigation/rendering tests.
- [ ] Verify the complete macOS 26/27 and Intel/Apple-silicon runtime matrix; locally available results are tracked in ../VERIFICATION.md.

Acceptance cases: category boundaries and rounding, invalid data, sorting/ties, duplicate and same-name cities, cancellation, hourly UTC selection across local DST/midnight, missing forecast horizon, TTL/jitter/backoff, concurrent requests, HTTP/offline failures, persistence and corruption, removal races, no dropdown-induced requests, accessible rendered UI, universal Debug/Release builds.

## 4. Release and distribution

- [x] Development ad-hoc signing separated from production Developer ID settings.
- [x] Sandbox/network entitlement, Hardened Runtime, universal Release configuration.
- [x] Required production identity/configuration preflight; no credentials in source.
- [x] Archive/export → app ZIP notarization → staple app → signed DMG → notarize/staple DMG → mount/verify → checksum.
- [x] Unsigned/ad-hoc CI and protected signed-candidate workflow with temporary credential cleanup.
- [x] Draft GitHub release helper, reviewed notes file and immutable versioned assets.
- [x] Homebrew cask generator requiring a public stable release and matching checksum.
- [ ] Supply actual Developer ID credentials, production bundle ID, GitHub repository and tap ownership.
- [ ] Run signed/notarized release and clean-machine/quarantined/offline acceptance.
- [ ] Publish GitHub release, then publish/test owned tap install/upgrade/uninstall/zap.

Manual installation: download Udara-<version>-universal.dmg, drag app into Applications. Homebrew uses that same artifact. No automatic updater; use Homebrew upgrades or replacement DMGs.

## Defaults and boundaries

App name Udara, English UI, free non-commercial v1. No charts, alerts, sync, or updater. Location detection was added in the 1.2.0 revision below. External credentials and repository ownership gate distribution, not local development. Execute sequentially: project/previews → city management → cache engine → integrated tests → release tooling → publication.

Reference: [Open-Meteo AQ](https://open-meteo.com/en/docs/air-quality-api), [geocoding](https://open-meteo.com/en/docs/geocoding-api), [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [Homebrew](https://docs.brew.sh/Cask-Cookbook).


## Current location revision — 1.2.0

- [x] Pin a non-removable Current location row above the separately sorted saved cities.
- [x] Offer Enable location in the default row. Only the native permission prompt grants access; previews never request access.
- [x] Use one-shot Core Location fixes at launch, hourly, after wake/clock changes, and on explicit retry. Reject old/inaccurate fixes and time out after 25 seconds.
- [x] Round coordinates to two decimal places and resolve area names with macOS 26 MapKit reverse geocoding; use Nearby area if name lookup fails.
- [x] Reuse hourly forecast caching for unchanged coordinates, invalidate readings when the area changes, and preserve server cooldowns.
- [x] Keep the most recent area/cache locally, without location history. Hide it until a fresh fix after relaunch. Clear it on permission denial; retain it during temporary failure for recovery.
- [x] Keep loading, denied, unavailable and disabled states in the pinned row. Reduce saved-city scroll height to fit the additional row.
- [x] Include optional-location privacy text, usage descriptions and sandbox entitlement.
- [ ] Verify a real permission grant and location fix on the user's Mac; automated tests use fixtures and do not grant OS permission.


## Menu bar display revision — 1.3.0

- [x] Always render the current highest available AQI alongside the icon; show a dash when unavailable.
- [x] Render the icon and number as one template image so macOS cannot collapse the label to icon-only. Preserve an accessible AQI/category label and automatic menu bar contrast.
- [x] Add Settings choices Udara icon (wind, default) and Dynamic AQI icon (category symbol).
- [x] Persist the preference in the existing atomic snapshot; older snapshots default safely to the Udara icon.
- [x] Keep preview preferences in memory and document the number's source in Settings.
