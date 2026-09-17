import { Hono } from 'hono';
import { decodeOpenMeteo, fetchOpenMeteo } from './providers/open-meteo';
import { decodeDOE, fetchDOE } from './providers/doe';
import { SourceError, type Bindings, type Fetcher, type Location } from './types';
import { positiveSetting, record } from './validation';

type Dependencies = { fetcher?: Fetcher; now?: () => number; cache?: Cache };
export function createApp(dependencies: Dependencies = {}) {
  const app = new Hono<{ Bindings: Bindings }>();
  const fetcher: Fetcher = dependencies.fetcher ?? ((url, init) => fetch(url, init));
  const clock = dependencies.now ?? Date.now;
  app.use('*', async (c, next) => {
    const started = performance.now();
    c.header('Cache-Control', 'no-store');
    c.header('X-Udara-Cache', 'BYPASS');
    c.header('X-Content-Type-Options', 'nosniff');
    await next();
    c.header("Server-Timing", `app;dur=${(performance.now() - started).toFixed(1)}`);
  });
  app.get('/health', c => c.json({ status: 'ok', service: 'udara-api', schema_version: 1 }));
  app.get('/v1/air-quality', async c => {
    const lat = c.req.query('lat'), lon = c.req.query('lon'), country = c.req.query('country')?.toUpperCase();
    if (!lat?.trim() || !lon?.trim() || !country || !/^[A-Z]{2}$/.test(country)
      || !Number.isFinite(Number(lat)) || Math.abs(Number(lat)) > 90
      || !Number.isFinite(Number(lon)) || Math.abs(Number(lon)) > 180) {
      return c.json({ error: { code: 'invalid_location', message: 'Provide lat, lon and the location country (ISO alpha-2).' } }, 400);
    }
    const metric = c.req.query('metric') ?? 'overall';
    if (!['overall', 'pm25'].includes(metric)) return c.json({ error: { code: 'invalid_metric' } }, 400);
    const location: Location = { latitude: Number(lat), longitude: Number(lon), country };
    const now = clock();
    const maxAge = positiveSetting(c.env.MAX_OBSERVATION_AGE_SECONDS, 7200, 86400);
    const doeRadius = positiveSetting(c.env.DOE_RADIUS_KM, 50, 200);
    const attempts: { source: string; reason: string }[] = [];
    const result = (observation: ReturnType<typeof decodeDOE>) => c.json({
      schema_version: 1, location, observation,
      observation_age_seconds: Math.max(0, Math.floor((now - Date.parse(observation.observed_at)) / 1000)),
      resolved_at: new Date(now).toISOString(), fallback: attempts.length ? attempts : null,
    });
    if (country === 'MY') {
      try {
        // Cache only the DOE station dataset, never location queries.
        const cache = dependencies.cache ?? (typeof caches !== 'undefined' ? caches.default : undefined);
        // Share one station dataset across coordinates, metrics and country spelling.
        // Use the request origin so the key belongs to this Worker's own hostname.
        const key = new Request(new URL('/_cache/doe-stations-v2', c.req.url).toString());
        let dataset: { payload: unknown; fetched_at: string } | undefined;
        if (cache) {
          try {
            const hit = await cache.match(key);
            if (hit) {
              const cached = await hit.json<{ payload: unknown; fetched_at: string }>();
              const fetched = Date.parse(cached.fetched_at);
              if (validDataset(cached.payload) && Number.isFinite(fetched) && fetched <= now && now - fetched < 300_000) {
                dataset = cached;
                c.header('X-Udara-Cache', 'HIT');
                c.header('X-Udara-Cache-Age', String(Math.floor((now - fetched) / 1000)));
              }
            }
          } catch { /* Ignore corrupt or unavailable cache storage. */ }
        }
        if (!dataset) {
          const payload = await fetchDOE(fetcher);
          if (!validDataset(payload)) throw new SourceError('unavailable');
          dataset = { payload, fetched_at: new Date(clock()).toISOString() };
          c.header('X-Udara-Cache', 'MISS');
          c.header('X-Udara-Cache-Age', '0');
          if (cache) {
            const write = cache.put(key, Response.json(dataset, { headers: { 'Cache-Control': 'public, max-age=300' } })).catch(() => {});
            try { c.executionCtx.waitUntil(write); } catch { await write; }
          }
        }
        // Location/metric misses do not invalidate the shared dataset or refetch DOE.
        const observation = decodeDOE(dataset.payload, location, clock(), dataset.fetched_at, doeRadius, maxAge, metric === 'pm25');
        return result(observation);
      } catch (error) {
        attempts.push({ source: 'doe', reason: error instanceof SourceError ? error.reason : 'unavailable' });
      }
    }
    c.header('X-Udara-Cache', 'BYPASS');
    c.res.headers.delete('X-Udara-Cache-Age');
    try {
      const observation = decodeOpenMeteo(await fetchOpenMeteo(fetcher, location), location, clock());
      if (metric === 'pm25' && !observation.pm25_index) throw new SourceError('no_usable_station');
      return result(observation);
    } catch (error) {
      attempts.push({ source: 'open_meteo', reason: error instanceof SourceError ? error.reason : 'unavailable' });
    }
    c.header('Retry-After', '300');
    return c.json({ error: { code: 'no_usable_observation', attempts } }, 503);
  });
  // Avoid exposing token-bearing upstream exceptions or request coordinates in logs.
  app.onError(() => new Response(JSON.stringify({ error: { code: 'internal_error' } }), {
    status: 500, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  }));
  return app;
}
export default createApp();

function validDataset(payload: unknown): boolean {
  const value = record(payload);
  return !value.error && !value.exceededTransferLimit && Array.isArray(value.features) && value.features.length > 0;
}
