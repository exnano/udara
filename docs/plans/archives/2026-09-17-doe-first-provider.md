# DOE-first Malaysia provider migration

> Archived 17 September 2026: backend and app integration implemented; production backend deployed and verified. See [verification record](../../VERIFICATION.md) for completion evidence. The 1.5.0 app release and [security remediation](../../security/2026-09-17-security-posture.md) remain separate follow-up work. The original planning and verification notes below are historical.

> Current decision: AQICN fallback is restored. DOE is primary in Malaysia; AQICN serves other countries and unavailable DOE observations.

## Requested scope

Prefer DOE Malaysia for Malaysian locations; use AQICN when DOE has no usable nearby observation. The user selected a Hono backend in this repository's `hono/` directory for Cloudflare Workers. Its domain and station examples are illustrative, not deployment configuration.

## Live verification — 17 September 2026, approximately 06:51 MYT

DOE's public ArcGIS layer and query endpoint returned HTTP 200:

https://eqms.doe.gov.my/api3/publicmapproxy/PUBLIC_DISPLAY/CAQM_MCAQM_Current_Reading/MapServer/0/query

The query returned 68 station records without a transfer-limit flag. Relevant fields include:

- `STATION_ID`, `STATION_LOCATION`, `STATE_NAME`, `LATITUDE`, `LONGITUDE`, `STATION_STATUS`
- `DATETIME`, `API`, `CLASS`, `PARAM_SELECTED`
- `SI_PM25`, `PM25_CONC`, `PM25_24H_AVG`, `PM25H_FLAG`, `FLAG_PM25AVG`

Use an explicit field allowlist, not `outFields=*`. Other fields include operational contact information unrelated to Udara. Use attribute latitude/longitude: the returned geometry in the initial query was rounded to whole degrees.

Shah Alam (CA20B, coordinates 3.104750 / 101.556192) returned API 156, PM2.5 sub-index 156, hourly PM2.5 field 68.093, and 24-hour PM2.5 field 65.225. The endpoint exposes pollutant information directly; AQICN is not required to supplement every DOE reading. Field units and quality-flag semantics should be confirmed before presentation beyond the documented 24-hour PM2.5 concentration.

### Timestamp interpretation

`DATETIME=1789624800000` decodes literally to 2026-09-17 06:00 UTC, nearly eight hours in the future at fetch time. DOE's own portal JavaScript (`https://eqms.doe.gov.my/js/app.b7aa2f9f.js`) formats this field using UTC date/hour components, displaying 06:00. AQICN independently reported the same Shah Alam observation at `2026-09-17T06:00:00+08:00`, API 156.

Evidence therefore supports interpreting this endpoint's numeric date components as Malaysian wall-clock time, converting to 2026-09-16T22:00:00Z. Isolate this provider-specific normalization and test it; do not apply an eight-hour correction to all providers or guess based on whether a date happens to be in the future. Reject future observations beyond a small clock tolerance.

### AQICN access

The current local `WAQI_TOKEN` successfully retrieved Shah Alam station 2621. The previously documented Invalid key condition no longer holds for this local check. No token was printed or written to fixtures.

AQICN attribution includes DOE and the World Air Quality Index Project. Its individual pollutant values are AQI sub-indices, not raw µg/m³ concentrations; the example in the supplied document must not be implemented as a concentration mapping.

## Model and source policy

- Preserve provider, index system, metric, station coordinates/name/ID, distance, observed time, fetched time, and attribution.
- DOE overall API and DOE PM2.5 sub-index must have distinct metric identifiers. Neither can be labeled US AQI. Preserve the existing PM2.5 focus through the sub-index where valid; show the exact index system in UI.
- DOE uses Malaysian API categories, including Unhealthy at 101–200. Do not reuse US AQI's 101–150 sensitive-groups classification.
- AQICN fallback must retain its reported index identity and originating agency. Missing PM2.5 must not silently become an overall reading labeled PM2.5.
- Malaysia: nearest usable DOE station within a configured, documented radius; fallback to AQICN for missing, invalid, stale, out-of-range or failed DOE responses.
- Outside Malaysia: AQICN. Country resolution must be explicit and reliable; a Malaysia bounding box includes neighboring countries and is insufficient.
- Validate timestamps, coordinates, finite/nonnegative values, station status, quality flags and complete upstream responses.
- Observation freshness depends on observed time, not successful fetch time. Do not force observations into the current exact-hour forecast model.
- Keep current location first. Mixed index scales require visible source/scale labels and a deliberate menu-bar/sorting policy, rather than silently treating values as interchangeable.

## Backend and caching decision

If adopting the proposed Worker, keep the AQICN secret server-side and pass a normalized versioned response to Swift. Use provider-specific cache policies. AQICN's published terms prohibit redistribution of cached/archived API data, so do not apply the document's generic KV/edge-cache strategy to AQICN without an appropriate agreement. Public organizational usage also has notification/agreement requirements.

If integrating directly, keep credentials outside the binary; the existing decision was per-user Keychain for public distribution, with `.env` allowed only for local assessment.

No new backend was deployed and no public app was switched during this verification.

## Implementation and validation sequence

1. Implement the selected Hono Worker and configure its deployment endpoint before Swift integration.
2. Add typed observation/station/index models and provider-specific decoding with sanitized fixtures.
3. Implement station matching, observed-time freshness and fallback; retain source/scale metadata.
4. Add provider-specific persistence and refresh rules; migrate legacy forecast cache safely.
5. Update Swift rows, settings, menu bar, sorting and attribution for observations and distinct scales.
6. Test Malaysia/outside-Malaysia routing, nearest usable station, radius boundary, missing PM2.5, stale/future observations, timezone conversion, malformed payloads, upstream throttling, partial failures and fallback recovery.
7. Validate local live DOE and AQICN responses, Swift builds, and rendered UI before release.

## Primary references

- DOE live layer: https://eqms.doe.gov.my/api3/publicmapproxy/PUBLIC_DISPLAY/CAQM_MCAQM_Current_Reading/MapServer/0?f=json
- DOE API calculation guide: https://eqms.doe.gov.my/Documents/APIMS/API_Calculation.pdf
- DOE public portal: https://eqms.doe.gov.my/
- AQICN API and usage terms: https://aqicn.org/api/
