import { describe, expect, it, vi } from 'vitest';
import type { Fetcher } from '../src/types';
import { createApp } from '../src/index';
import { decodeDOE, doeURL } from '../src/providers/doe';

const now = Date.parse('2026-09-16T22:51:00Z');
const location = { latitude: 3.10475, longitude: 101.556192, country: 'MY' };
const attributes = { STATION_ID: 'TEST', STATION_LOCATION: 'Test station', STATION_STATUS: 1,
  LATITUDE: location.latitude, LONGITUDE: location.longitude, DATETIME: Date.parse('2026-09-17T06:00:00Z'),
  API: 125, SI_PM25: 110, PM25_24H_AVG: 51, FLAG_PM25AVG: null };
const doe = (overrides = {}) => ({ features: [{ attributes: { ...attributes, ...overrides } }] });
const path = '/v1/air-quality?lat=3.10475&lon=101.556192&country=MY';
const env = {};
const decode = (payload: unknown) => decodeDOE(payload, location, now, new Date(now).toISOString(), 50, 7200);

describe('DOE normalization', () => {
  it('normalizes Malaysian wall time and keeps API scale and PM2.5 distinct', () => {
    const value = decode(doe());
    expect(value.observed_at).toBe('2026-09-16T22:00:00.000Z');
    expect(value.index).toMatchObject({ value: 125, scale: 'MY_API', category: 'Unhealthy' });
    expect(value.pm25_index?.value).toBe(110);
    expect(value.pm25_24h_concentration?.value).toBe(51);
  });
  it.each([{ API: null }, { API: -1 }, { LATITUDE: 100 }, { STATION_STATUS: 0 },
    { DATETIME: attributes.DATETIME - 3 * 3600_000 }, { DATETIME: attributes.DATETIME + 2 * 3600_000 }])('rejects invalid station %j', override => {
    expect(() => decode(doe(override))).toThrow();
  });
  it('omits flagged PM2.5 and does not substitute overall API', () => {
    expect(decode(doe({ FLAG_PM25AVG: 'INS' })).pm25_index).toBeNull();
    expect(decode(doe({ SI_PM25: null })).pm25_index).toBeNull();
  });
  it('chooses nearest usable station, not first or nearest stale station', () => {
    const payload = { features: [{ attributes: { ...attributes, STATION_ID: 'far', LATITUDE: 3.2 } },
      { attributes: { ...attributes, STATION_ID: 'stale', DATETIME: 0 } }, { attributes }] };
    expect(decode(payload).station.id).toBe('TEST');
  });
  it('rejects partial dataset and out-of-radius stations', () => {
    expect(() => decode({ ...doe(), exceededTransferLimit: true })).toThrow();
    expect(() => decode(doe({ LATITUDE: 6 }))).toThrow();
  });
  it('uses a field allowlist without contact information or geometry', () => {
    expect(doeURL()).not.toContain('outFields=*');
    expect(doeURL()).not.toContain('EMAIL');
    expect(new URL(doeURL()).searchParams.get('returnGeometry')).toBe('false');
  });
});
describe('provider routing', () => {
  it('uses DOE for Malaysia', async () => {
    const fetcher = vi.fn<Fetcher>(async () => Response.json(doe()));
    const res = await createApp({ fetcher, now: () => now }).request(path, {}, env);
    expect(res.status).toBe(200);
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(String(fetcher.mock.calls[0][0])).toContain('eqms.doe.gov.my');
  });
  it.each([429, 503])('returns unavailable on upstream %s with failed fallback', async status => {
    const fetcher = vi.fn<Fetcher>(async () => new Response('', { status }));
    const res = await createApp({ fetcher, now: () => now }).request(path, {}, env);
    expect(res.status).toBe(503);
    expect(fetcher).toHaveBeenCalledTimes(2);
    expect(res.headers.get('Cache-Control')).toBe('no-store');
  });
  it('fails safely outside Malaysia if Open-Meteo is unavailable', async () => {
    const fetcher = vi.fn<Fetcher>();
    const res = await createApp({ fetcher }).request(path.replace('country=MY', 'country=SG'), {}, env);
    expect(res.status).toBe(503);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it.each([{ SI_PM25: null }, { DATETIME: 0 }])('does not substitute an unusable PM2.5 observation', async override => {
    const fetcher = vi.fn<Fetcher>(async () => Response.json(doe(override)));
    const res = await createApp({ fetcher, now: () => now }).request(path + '&metric=pm25', {}, env);
    expect(res.status).toBe(503);
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
  it('sanitizes upstream errors', async () => {
    const fetcher = vi.fn<Fetcher>(async () => { throw new Error('private upstream details'); });
    const res = await createApp({ fetcher, now: () => now }).request(path, {}, env);
    expect(res.status).toBe(503);
    expect(await res.text()).not.toContain('private');
  });
  it.each(['', '?lat=&lon=100&country=MY', '?lat=NaN&lon=100&country=MY', '?lat=91&lon=100&country=MY'])('validates query %s', async query => {
    const fetcher = vi.fn<Fetcher>();
    expect((await createApp({ fetcher }).request('/v1/air-quality' + query, {}, env)).status).toBe(400);
    expect(fetcher).not.toHaveBeenCalled();
  });
});
describe('DOE cache', () => {
  it('reuses fresh data without a request', async () => {
    const fetchedAt = new Date(now - 60_000).toISOString();
    const cache = { match: vi.fn(async () => Response.json({ payload: doe(), fetched_at: fetchedAt })), put: vi.fn() };
    const fetcher = vi.fn<Fetcher>();
    const res = await createApp({ fetcher, now: () => now, cache: cache as unknown as Cache }).request(path, {}, env);
    expect(res.status).toBe(200);
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('rejects stale observations in a fresh cache', async () => {
    const cache = { match: vi.fn(async () => Response.json({ payload: doe({ DATETIME: 0 }), fetched_at: new Date(now).toISOString() })), put: vi.fn() };
    const fetcher = vi.fn<Fetcher>(async () => Response.json(doe({ DATETIME: 0 })));
    const res = await createApp({ fetcher, now: () => now, cache: cache as unknown as Cache }).request(path, {}, env);
    expect(res.status).toBe(503);
    expect(cache.put).not.toHaveBeenCalled();
  });
});


describe('Open-Meteo fallback', () => {
  const payload = { latitude: 3.1, longitude: 101.5, hourly: { time: [Math.floor(now / 3600_000) * 3600], us_aqi: [160], us_aqi_pm2_5: [120] } };
  it('uses model PM2.5 outside Malaysia', async () => {
    const fetcher = vi.fn<Fetcher>(async () => Response.json(payload));
    const res = await createApp({ fetcher, now: () => now }).request(path.replace('MY', 'SG'), {}, env);
    expect(res.status).toBe(200);
    expect((await res.json<any>()).observation.pm25_index).toEqual({value:120,scale:'US_AQI',metric:'pm25'});
    expect(String(fetcher.mock.calls[0][0])).toContain('air-quality-api.open-meteo.com');
  });
  it('falls back when DOE fails', async () => {
    const fetcher = vi.fn<Fetcher>().mockResolvedValueOnce(new Response('', {status:503})).mockResolvedValueOnce(Response.json(payload));
    const res = await createApp({fetcher, now: () => now}).request(path, {}, env);
    expect(res.status).toBe(200);
    expect((await res.json<any>()).observation.source).toBe('open_meteo');
  });
  it.each([null, -1])('rejects unusable PM2.5 %s', async value => {
    const fetcher = vi.fn<Fetcher>(async () => Response.json({...payload,hourly:{...payload.hourly,us_aqi_pm2_5:[value]}}));
    expect((await createApp({fetcher,now:()=>now}).request(path.replace('MY','SG'),{},env)).status).toBe(503);
  });
  it('never reuses the previous hour estimate', async () => {
    const fetcher = vi.fn<Fetcher>(async () => Response.json(payload));
    expect((await createApp({fetcher,now:()=>now+3600_000}).request(path.replace('MY','SG'),{},env)).status).toBe(503);
  });
});

describe('edge cache performance', () => {
  it('shares dataset across locations and reports hits without refetching on coverage misses', async () => {
    const cache = { match: vi.fn(async () => Response.json({ payload: doe(), fetched_at: new Date(now - 30_000).toISOString() })), put: vi.fn() };
    const fetcher = vi.fn<Fetcher>();
    const app = createApp({ cache: cache as unknown as Cache, fetcher, now: () => now });
    const hit = await app.request(path, {}, env);
    expect(hit.headers.get('X-Udara-Cache')).toBe('HIT');
    expect(hit.headers.get('X-Udara-Cache-Age')).toBe('30');
    expect(hit.headers.get('Server-Timing')).toContain('app;dur=');
    const miss = await app.request(path.replace('lat=3.10475', 'lat=6'), {}, env);
    expect(miss.status).toBe(503);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('refreshes expired data and survives a failed cache write', async () => {
    const cache = { match: vi.fn(async () => Response.json({ payload: doe(), fetched_at: new Date(now - 300_000).toISOString() })), put: vi.fn(async () => { throw new Error('cache unavailable'); }) };
    const fetcher = vi.fn<Fetcher>(async () => Response.json(doe()));
    const res = await createApp({ cache: cache as unknown as Cache, fetcher, now: () => now }).request(path, {}, env);
    expect(res.status).toBe(200);
    expect(res.headers.get('X-Udara-Cache')).toBe('MISS');
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(cache.put).toHaveBeenCalledTimes(1);
  });
  it('does not cache provider error payloads', async () => {
    const cache = { match: vi.fn(async () => undefined), put: vi.fn() };
    const fetcher = vi.fn<Fetcher>(async () => Response.json({ error: { message: 'error' } }));
    const res = await createApp({ cache: cache as unknown as Cache, fetcher, now: () => now }).request(path, {}, env);
    expect(res.status).toBe(503);
    expect(cache.put).not.toHaveBeenCalled();
  });
});
