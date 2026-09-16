# Exnano Udara

Project code name: **Exnano Udara**. Application name: **Udara.app** (display name **Udara**). Production bundle identifier: **`io.exnano.udara`**.

A native macOS menu bar app for air quality estimates in the cities you care about.

Source repository: [exnano/udara](https://github.com/exnano/udara).

- Menu bar AQI number with a saved choice of Udara or dynamic category icon.
- Permanent current-location row with optional macOS location detection.
- Saved cities sorted by descending estimated US AQI.
- Six quality categories with icons, colours, and text labels.
- Keyless Open-Meteo/CAMS forecasts, downloaded hourly per city.
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

Open `Sources/UdaraApp/PreviewFixtures.swift` in Xcode and choose Editor → Canvas. Named `#Preview` entries use fixed-time in-memory fixtures and never contact a service or modify saved preferences. The Debug-only `--preview-host` option opens the full dropdown as an inspectable window. Add `--light`, `--dark`, or `--reduced-transparency` to inspect appearance and `--empty` for onboarding; search in this mode uses local sample results.

## Versioning

App version/build live in `Config/Version.xcconfig`. Use `python3 scripts/version.py bump patch` for fixes, `bump minor` for features, and `bump major` for breaking changes. Every bump also increments the build. Preview with `--dry-run`, and record changes in [CHANGELOG.md](CHANGELOG.md).

See the [versioning guide](docs/VERSIONING.md) for examples and release/tag instructions. `Package.swift`'s `swift-tools-version` is not the app version.

## Data and privacy

Values are **estimated US AQI**, not IQAir readings or live station observations. Data comes from [Open-Meteo](https://open-meteo.com/en/docs/air-quality-api), using CAMS ENSEMBLE and CAMS global forecasts. Geocoding is supplied by Open-Meteo/GeoNames. AQI values are rounded to whole numbers for display and classification. Source data attribution and applicable licences: [Open-Meteo licence](https://open-meteo.com/en/licence), [CAMS](https://atmosphere.copernicus.eu/).

The hosted free API is for **non-commercial use**. Reassess the service agreement before commercial use or large-scale distribution. Caching reduces requests; it does not confer unlimited service capacity.

No account or analytics. Location permission is optional: enable it from the pinned Current location row. Udara takes a one-shot fix at launch, hourly, after wake, or when you explicitly retry. Coordinates are rounded to two decimal places before being sent to Open-Meteo for AQI and Apple MapKit for an area name. Only the latest area and forecast are cached locally; no travel history is kept. Revoking permission clears the current-location cache. Saved cities remain usable without location access. Searches and selected coordinates are sent to Open-Meteo; the service also receives your IP address. Saved cities, forecasts, and search results remain in the app's local Application Support directory (`Udara/state-v1.json` inside the sandbox container).

Opening the dropdown does not start a request. Forecasts become eligible for download after one hour, with up to one minute of randomized delay; the running app checks due work every minute. Server retry deadlines still apply. Existing daily deadlines migrate automatically without clearing saved cities. Current-hour values change locally; old samples are never carried forward. Downloads can retrieve revised forecasts sooner, but values may remain unchanged between provider model runs. Search queries use a 400 ms debounce and 30-day cache. Errors preserve successful forecasts and persist retry deadlines. Unsupported/corrupt saved files are preserved; the app opens a temporary in-memory session with a visible warning rather than overwriting them.

## Distribution

Preview renders: [light](docs/previews/light.png) · [dark](docs/previews/dark.png) · [reduced transparency](docs/previews/reduced-transparency.png).

See [release instructions](docs/RELEASING.md), [implementation plan](docs/plans/2026-09-16-udara-menubar-app.md), and [verification record](docs/VERIFICATION.md).

Once releases exist, manual installation uses the signed DMG's Applications shortcut. Homebrew installs the same DMG through an owned tap. Source is hosted at `exnano/udara`. Public DMG releases and the Homebrew tap are not yet published.
