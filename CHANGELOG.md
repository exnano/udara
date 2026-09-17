# Changelog

## 1.5.1 (8) — 2026-09-17

- Replace AQICN with Open-Meteo fallback while retaining DOE priority in Malaysia.
- Label model readings as Estimated US AQI and forecast validity, expiring at the UTC hour boundary.
- Correct location permission disclosure and retire the cancelled WAQI migration plan.

## 1.5.0 (7) — 2026-09-17

- Remove GitHub Actions builds; use local testing, notarization and manual release publication.

- Refresh About with Exnano branding, version, source/freshness explanations, privacy details and support links.

- Use DOE first in Malaysia and AQICN elsewhere or when DOE is unavailable.
- Scroll the GPS row together with saved cities and omit download-age text.

- Connect the Mac app to the Udara backend with separate development and production API URLs from ignored `.env`.
- Display station PM2.5 indices with source scale, observation age, distance and agency attribution; retain readings in memory only.
- Prefer current location in the menu bar and group saved readings by scale.
- Require a configured HTTPS backend before building a distribution release.

## 1.4.0 (6) — 2026-09-16

- Use the supplied Udara Icon Composer artwork as the application icon.

- Allow Settings descriptions to wrap fully and scroll within the menu window.

- Move each saved city’s action menu to the bottom-right, with a larger rounded control.

- Focus on estimated PM2.5 US AQI for haze: city sorting, menu bar values and category icons all use PM2.5-specific AQI.
- Show hourly PM2.5 concentration in µg/m³ separately from AQI, with the averaging distinction explained in Settings.
- Invalidate legacy overall-AQI caches while preserving cities, location, icon preferences and server retry deadlines.

## 1.3.1 (5) — 2026-09-16

- Fix release architecture validation by checking each universal slice individually.

- Release, draft-release and Homebrew cask tooling load ignored local `.env` settings, with shell/CI overrides and literal parsing. Added `.env.example` and configuration guide.

## 1.3.0 (4) — 2026-09-16

### Added

- Settings choice between the Udara wind icon and a dynamic AQI-category icon, persisted locally.
- Explicit icon-plus-number rendering in the menu bar, with a dash when no current AQI exists. The number remains the highest available AQI across current location and saved cities.
- Deterministic menu bar previews and preference/migration tests.

## 1.2.0 (3) — 2026-09-16

### Added

- Permanent Current location row above the saved cities, with optional Core Location permission and city-scale detection.
- Hourly and wake-time location checks, modern MapKit area-name lookup, and cached forecasts for the detected area.
- Permission-denied, locating and unavailable states; saved cities work independently of location permission.
- Location cache/movement/revocation tests and deterministic location-state previews.

## 1.1.0 (2) — 2026-09-16

### Changed

- Download forecasts hourly with up to one minute of scheduling jitter; migrate daily deadlines while retaining saved cities and server retry limits.
- Adopt native SwiftUI Liquid Glass for navigation and actions, with solid AQI badges and reduced-transparency controls.
- Add hourly-expiry/migration coverage and light, dark, and reduced-transparency render fixtures.

### Added

- Shared app version/build configuration, patch/minor/major/build bump commands, release consistency checks, and a versioning guide.
- Version and build number displayed together in Settings.

### Initial implementation (not yet published)

- Native macOS menu bar app with saved cities ordered by estimated US AQI.
- Open-Meteo forecasts, daily local caching, city search, and explicit stale-data states.
- AQI category icons/colours, light/dark previews, and automated tests.
- Universal build, Developer ID/notarization tooling, GitHub DMG and Homebrew distribution scripts.
