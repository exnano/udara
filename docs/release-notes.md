# Udara 1.5.0

- Prefer DOE station observations in Malaysia, with AQICN for other countries and fallback coverage.
- Show PM2.5 station indices, their source scale, observation age, station distance and attribution.
- Use the deployed Udara API with a five-minute DOE dataset cache.
- Keep the current-location row inside the scrolling list and remove download-age text.
- Refresh About, privacy explanations and source links.
- Build and notarize locally; GitHub Actions workflows are removed.

Download the universal DMG and drag Udara into Applications, or run `brew update && brew upgrade --cask udara` using the exnano/tap tap. Requires macOS 26 or later.

Known limitations: the security evaluation remains open, including API quota-abuse protection, location-permission wording, response-size limits and operational monitoring. See `docs/security/2026-09-17-security-posture.md`. The complete macOS/CPU and clean-machine offline acceptance matrix has not been verified.
