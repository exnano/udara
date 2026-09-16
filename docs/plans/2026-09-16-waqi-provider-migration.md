# WAQI provider migration — assessment and proposed implementation

## Verified on 16 September 2026

- WAQI supports station/city AQI, coordinate lookup, station search, originating-agency attribution and reporting timestamps: https://aqicn.org/api/ and https://aqicn.org/json-api/doc/.
- Two authenticated coordinate requests for Kuala Lumpur and Petaling Jaya returned `status=error`, `data=Invalid key`. The token was read from ignored `.env` in memory and was not printed, embedded, committed or written to a request log. No usable live observation was obtained.
- Source switching alone cannot guarantee fresh readings: station reporting can lag. The UI must distinguish the observation timestamp from download time.
- WAQI's published terms require WAQI and originating-EPA attribution, prohibit paid-app use and redistribution of cached/archived data, and require explicit agreement for public use by for-profit corporations. Confirm the intended Exnano distribution and any permitted caching with WAQI before public release.

## Credential decision and current scope

Selected for a future public integration: users provide their own token through Settings, stored in macOS Keychain. A local developer helper may import WAQI_TOKEN from `.env` into Keychain without bundling it. Public binaries must contain no shared credential.

Alternative: Exnano-hosted authenticated proxy with a server-side token, abuse protection, monitoring, hosting configuration and provider agreement. This expands the original no-backend scope; do not create hosting or route users through a shared token without selecting this approach.

## Local dataset assessment first

The user subsequently deferred app/Keychain changes to inspect the dataset first. The partial domain refactor was reverted; the running/public app remains unchanged.

Set `WAQI_TOKEN` in ignored `.env`, then run:

```sh
python3 scripts/assess-waqi.py --compare-open-meteo
# Or inspect a specific place:
python3 scripts/assess-waqi.py --city "Kuala Lumpur" 3.139 101.6869 --compare-open-meteo
```

Defaults cover Kuala Lumpur, Petaling Jaya, Shah Alam and George Town. Output reports the station, distance from the requested coordinates, AQI, observation timestamp/age, dominant pollutant and attribution. It prints no token or authenticated request URL and writes no observation archive. The optional comparison fetches Open-Meteo's current-hour model estimate; differences alone do not establish accuracy.

The latest local recheck still returned Invalid key. Dataset freshness and coverage cannot yet be established. Activate/check the token at https://aqicn.org/data-platform/token/ and update `.env` locally; do not post it in chat.

## Migration work (deferred)

- [ ] Validate an active token and inspect actual station payloads, timestamps and attribution.
- [ ] Implement an injectable WAQI observation provider; handle HTTP failures and HTTP-200 API errors, missing/non-numeric AQI, timestamps with offsets, source attribution and station identity.
- [ ] Separate station observations from model forecasts. Do not manufacture hourly samples from the latest station reading or apply the existing exact-current-hour forecast lookup to observations.
- [ ] Preserve saved-city preferences and coordinates. Resolve each city/current location to a station; show the returned station name so a nearby station is not misrepresented as a city-wide reading. Deduplicate requests when cities resolve to the same station.
- [ ] Keep the established hourly automatic refresh initially. Display station observation age independently of last successful fetch and clearly mark delayed/unavailable readings; choose and document a freshness limit using live-feed evidence.
- [ ] Add token setup/update/removal and actionable missing/invalid-token errors. Redact request URLs and credentials in errors/logs. Keep previews offline with synthetic fixtures.
- [ ] Replace Estimated US AQI and Open-Meteo forecast wording with accurate WAQI station/scale labels. Include per-station agency links plus WAQI attribution.
- [ ] Preserve retry/backoff/concurrency limits; separate provider cache namespaces and avoid silently mixing old forecast values with new observations. Use in-memory observation state initially unless the permitted local-cache policy is confirmed; do not redistribute cached data.
- [ ] Test decoding, timestamps, stale stations, station mapping/deduplication, token errors, credential replacement, offline behavior, current location and menu bar selection.
- [ ] Verify a real station response and rendered UI before bumping, notarizing or publishing the replacement provider.

The current public release remains on Open-Meteo. This document records the migration decision and blockers; no WAQI-based release has been produced.
