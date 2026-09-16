# Udara

A native macOS menu bar app for air quality estimates in the cities you care about.

- Saved cities sorted by descending estimated US AQI.
- Six quality categories with icons, colours, and text labels.
- Keyless Open-Meteo/CAMS forecasts, downloaded once per 24 hours per city.
- Current-hour display from a local forecast cache; explicit overdue/unavailable states.
- City search, local persistence, keyboard navigation, and light/dark appearance.

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

Open `Sources/UdaraApp/PreviewFixtures.swift` in Xcode and choose Editor → Canvas. Named `#Preview` entries use fixed-time in-memory fixtures and never contact a service or modify saved preferences. The Debug-only `--preview-host` option opens the full dropdown as an inspectable window. Add `--empty` for onboarding; search in this mode uses local sample results.

## Data and privacy

Values are **estimated US AQI**, not IQAir readings or live station observations. Data comes from [Open-Meteo](https://open-meteo.com/en/docs/air-quality-api), using CAMS ENSEMBLE and CAMS global forecasts. Geocoding is supplied by Open-Meteo/GeoNames. AQI values are rounded to whole numbers for display and classification. Source data attribution and applicable licences: [Open-Meteo licence](https://open-meteo.com/en/licence), [CAMS](https://atmosphere.copernicus.eu/).

The hosted free API is for **non-commercial use**. Reassess the service agreement before commercial use or large-scale distribution. Caching reduces requests; it does not confer unlimited service capacity.

No account, analytics, or location permission. Searches and selected coordinates are sent to Open-Meteo; the service also receives your IP address. Saved cities, forecasts, and search results remain in the app's local Application Support directory (`Udara/state-v1.json` inside the sandbox container).

Opening the dropdown does not start a request. Forecasts refresh after 24 hours plus up to 15 minutes of jitter. Current-hour values change locally; old samples are never carried forward. Search queries use a 400 ms debounce and 30-day cache. Errors preserve successful forecasts and persist retry deadlines. Unsupported/corrupt saved files are preserved; the app opens a temporary in-memory session with a visible warning rather than overwriting them.

## Distribution

Preview renders: [light](docs/previews/light.png) · [dark](docs/previews/dark.png).

See [release instructions](docs/RELEASING.md), [implementation plan](docs/plans/2026-09-16-udara-menubar-app.md), and [verification record](docs/VERIFICATION.md).

Once releases exist, manual installation uses the signed DMG's Applications shortcut. Homebrew installs the same DMG through an owned tap. No live repository or download URL is claimed until the owner configures and publishes them.
