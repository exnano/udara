# Udara API — Hono / Cloudflare Workers


## Local development

```sh
cd hono
bun install --frozen-lockfile
bun run dev
```

- Health: `http://localhost:8787/health`
- PM2.5: `http://localhost:8787/v1/air-quality?lat=3.0738&lon=101.5183&country=MY&metric=pm25`

Root `.env` configures the Mac app API URL separately. Tokens remain server-side. Restart Wrangler after changing `.dev.vars`.

## API behavior

`GET /v1/air-quality?lat=<latitude>&lon=<longitude>&country=MY&metric=pm25`

`country` is the requested city's ISO country code, not the device's IP country. `metric` defaults to `overall`; use `pm25` to require a usable PM2.5 sub-index. The nearest usable DOE station within `DOE_RADIUS_KM` is selected. The default radius is a provisional 50 km coverage limit; it does not imply uniform conditions across that area.

The schema-version-1 response retains station identity, distance, source `doe`, Malaysian index scale `MY_API`, overall index, separate nullable PM2.5 sub-index, nullable 24-hour PM2.5 concentration, observation/download times and attribution. Never substitute the overall index for missing PM2.5. DOE observations older than two hours or over five minutes in the future are rejected. The DOE-specific timestamp correction is documented in the project plan.

- 400: invalid location or metric.
- Outside Malaysia, query Open-Meteo directly. Its result is validated for proximity and freshness.
- 503 `no_usable_observation`: DOE failed, is stale, or has no usable nearby station. Includes a 300-second retry hint. Open-Meteo fallback is attempted first.
- 500: invalid server configuration or unexpected failure; no raw error details returned.

The allowlisted DOE station dataset is cached for **five minutes** through Cloudflare Cache API and shared across locations and metrics on the same hostname. Even a location without nearby coverage reuses this dataset. Station proximity, requested metric and observation age are checked on every request; stale observations are never served as fresh data. Invalid upstream datasets are not cached, and a cache write failure does not discard a successful response.

The cache is local to each Cloudflare data centre, so a cold region still fetches DOE. There is no KV, long-term observation archive, stale-response serving or cross-request refresh lock. API responses use `Cache-Control: no-store`; Open-Meteo responses bypass caching in this implementation. Upstream requests time out after eight seconds. Cross-request persistent provider backoff is not implemented.

Response diagnostics:

- `X-Udara-Cache: HIT`: DOE dataset reused; `X-Udara-Cache-Age` gives dataset download age in seconds, not observation age.
- `X-Udara-Cache: MISS`: DOE dataset downloaded and queued for caching.
- `X-Udara-Cache: BYPASS`: Open-Meteo, health or an uncached error response.
- `Server-Timing: app;dur=...`: Worker processing time in milliseconds.

The JSON `observed_at` and `observation_age_seconds` describe measurement age independently of caching.

## Validate and deploy

```sh
bun run check
bun run test
bun run build # dry run
bunx wrangler login
bun run deploy
```

Deployment runs locally using the authenticated Wrangler account. `wrangler.jsonc` selects Exnano Creative and the `udara.exnano.io` custom domain. Root `.env` uses `UDARA_API_URL_PRODUCTION=https://udara.exnano.io` for Release builds; Debug stays on `http://localhost:8787`. No GitHub Actions deployment is required. Local development does not deploy resources.

Observability is disabled by default to avoid logging user coordinates. Configure appropriate Cloudflare abuse/rate controls before a public rollout. DOE's public endpoint is not a guaranteed API SLA.


## Production endpoints

Deployed on 2026-09-17:

- API base: **https://udara.exnano.io**
- Health: https://udara.exnano.io/health
- Worker fallback hostname: https://exn-udara.exnano-creative.workers.dev
- Worker: `exn-udara`, account Exnano Creative.


The earlier proposed `exn-udara.pages.dev` is a Cloudflare Pages hostname and is not used by this standalone Worker.

Check the deployed cache (repeat the request):

```sh
curl -i 'https://udara.exnano.io/v1/air-quality?lat=3.0738&lon=101.5183&country=MY&metric=pm25'
```

A warm DOE response reports `X-Udara-Cache: HIT`. The first request after expiry may report `MISS`. See `docs/VERIFICATION.md` in the repository root for deployment measurements.

## Provider revision — 1.5.1

DOE remains primary in Malaysia; Open-Meteo supplies current UTC-hour PM2.5 model estimates elsewhere and on DOE failure. AQICN is removed; no API token is required. The existing schema uses `source=open_meteo`, `scale=US_AQI`, and `station` for model grid metadata. For this source, `observed_at` means forecast validity time, not measurement time or model run age. Clients must label it Estimated US AQI and Forecast valid. The estimate expires at the next UTC hour. Model concentration is not misrepresented as a 24-hour measured concentration. DOE retains its five-minute dataset cache; Open-Meteo currently bypasses server caching.
