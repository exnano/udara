# Exnano Udara

Project code name: **Exnano Udara**. Application name: **Udara.app** (display name **Udara**). Production bundle identifier: **`io.exnano.udara`**.

A native macOS menu bar app for air quality estimates in the cities you care about.

Source repository: [exnano/udara](https://github.com/exnano/udara).

- Menu bar AQI number with a saved choice of Udara or dynamic category icon.
- Permanent current-location row with optional macOS location detection.
- Saved cities sorted by descending estimated PM2.5 AQI.
- Six quality categories with icons, colours, and text labels.
- DOE Malaysia station readings with keyless Open-Meteo/CAMS model fallback.
- Current-hour display from a local forecast cache; explicit overdue/unavailable states.
- City search, local persistence, keyboard navigation, and light/dark appearance.
- Native SwiftUI Liquid Glass controls with a solid reduced-transparency fallback.

## Development

Requires **Xcode 27.0 / Swift 6.4**. The application targets **macOS 26+**.

```sh
open Udara.xcodeproj
./scripts/run.sh
./scripts/run.sh --preview-host
swift test
./scripts/test.sh
./scripts/build.sh Release
```

The native Xcode project is the source of truth; no generator or external Swift package dependencies are required. `Package.swift` provides an independent test harness for the same core sources. Its macOS 15 floor applies only to the test library, not the distributed app.

The app icon source is `Udara.icon`, editable in Icon Composer. Both Xcode build configurations use the `Udara` app icon name and compile the artwork automatically; no manual ICNS export is needed.

Open `Sources/UdaraApp/PreviewFixtures.swift` in Xcode and choose Editor → Canvas. Named `#Preview` entries use fixed-time in-memory fixtures and never contact a service or modify saved preferences. The Debug-only `--preview-host` option opens the full dropdown as an inspectable window. Add `--light`, `--dark`, or `--reduced-transparency` to inspect appearance and `--empty` for onboarding; search in this mode uses local sample results.

## Versioning

App version/build live in `Config/Version.xcconfig`. Use `python3 scripts/version.py bump patch` for fixes, `bump minor` for features, and `bump major` for breaking changes. Every bump also increments the build. Preview with `--dry-run`, and record changes in [CHANGELOG.md](CHANGELOG.md).

See the [versioning guide](docs/VERSIONING.md) for examples and release/tag instructions. `Package.swift`'s `swift-tools-version` is not the app version.

## Data and privacy

DOE readings show the Malaysian PM2.5 API. Open-Meteo fallback shows **estimated PM2.5 US AQI**, not station observations, with Open-Meteo/CAMS attribution. The two scales are labelled separately. DOE may supply a measured 24-hour concentration; model concentrations are not presented as that quantity. Forecast validity identifies the estimated hour, not the model run age.

The hosted free API is for **non-commercial use**. Reassess the service agreement before commercial use or large-scale distribution. Caching reduces requests; it does not confer unlimited service capacity.

No account or analytics. Location permission is optional. One-shot GPS fixes are rounded to two decimal places before Apple MapKit reverse geocoding and requests to the Udara backend on Cloudflare. The backend uses DOE or sends requested coordinates to Open-Meteo for model estimates. City searches use Open-Meteo/GeoNames. Services receive the connecting client's IP (the backend connects to forecast providers). Only the latest approximate area is saved, with no travel history; permission revocation clears it. Saved cities and search preferences remain in local sandbox Application Support. Air-quality responses are held in memory.

Opening the dropdown does not start a request. Forecasts become eligible for download after one hour, with up to one minute of randomized delay; the running app checks due work every minute. Server retry deadlines still apply. Existing daily deadlines migrate automatically without clearing saved cities. Current-hour values change locally; old samples are never carried forward. Downloads can retrieve revised forecasts sooner, but values may remain unchanged between provider model runs. Search queries use a 400 ms debounce and 30-day cache. Errors preserve successful forecasts and persist retry deadlines. Unsupported/corrupt saved files are preserved; the app opens a temporary in-memory session with a visible warning rather than overwriting them.

## Distribution

Preview renders: [light](docs/previews/light.png) · [dark](docs/previews/dark.png) · [reduced transparency](docs/previews/reduced-transparency.png).

See [release instructions](docs/RELEASING.md), [implementation plan](docs/plans/2026-09-16-udara-menubar-app.md), and [verification record](docs/VERIFICATION.md).

Download the signed and notarized [latest DMG](https://github.com/exnano/udara/releases/latest), open it, and drag Udara into Applications.

Or install the same build through the [Exnano Homebrew tap](https://github.com/exnano/homebrew-tap):

```sh
brew install --cask exnano/tap/udara
```

Update with `brew update && brew upgrade --cask udara`. Requires macOS 26 or later; universal Apple silicon/Intel build. Releases are built, tested and notarized locally with Xcode 27.0, then published manually. GitHub Actions is not used. See [the release guide](docs/RELEASING.md).

## Backend

The [Hono backend](hono/README.md) provides DOE-first Malaysia observations with Open-Meteo fallback for Cloudflare Workers. It has independent dependencies, tests, local secrets and deployment configuration. Version 1.5.1 connects to this backend. AQICN was removed after the 1.5.0 release.

### App API configuration

Set the ignored root `.env`:

```dotenv
UDARA_API_URL_DEVELOPMENT=http://localhost:8787
UDARA_API_URL_PRODUCTION=https://udara.exnano.io
```

Keep the backend running with `cd hono && bun run dev`. From the repository root, run `./scripts/run.sh` to build and launch the real Debug app (no preview fixtures). Debug uses a separate bundle identifier from the installed production app, so saved cities may differ.

Build/test/release scripts generate ignored `Config/API.local.xcconfig` containing only URLs. For direct Xcode builds, run `python3 scripts/configure-api.py Debug` after editing `.env`, then build the shared Udara scheme. Xcode does not load `.env` at runtime; rebuild after changing URLs. Development permits HTTP only on localhost/loopback. Release requires `UDARA_API_URL_PRODUCTION` set to a deployed HTTPS endpoint; it never falls back to the development URL. The production backend is deployed at https://udara.exnano.io, with a five-minute DOE dataset cache at each Cloudflare edge location. Open-Meteo responses remain uncached.

City search continues to use Open-Meteo geocoding. Existing city names resolve country codes where possible; unidentified legacy cities should be removed and added again. Backend requests include `metric=pm25` so missing DOE PM2.5 triggers Open-Meteo fallback. Readings stay in memory and are checked every ten minutes (plus scheduling jitter). DOE observations expire after two hours; model estimates expire at the next UTC hour. Saved cities/preferences remain on disk. Station data is never used as a forecast or relabeled across index systems.

The backend uses DOE in Malaysia with Open-Meteo fallback, and Open-Meteo directly outside Malaysia. The GPS row scrolls with saved locations; rows display DOE observation age or model forecast validity, not download age.
