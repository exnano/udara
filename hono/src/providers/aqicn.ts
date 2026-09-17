import { SourceError, type Fetcher, type Location, type Observation } from '../types';
import { category, coordinates, distance, nonnegative, record, usableTime } from '../validation';
export async function fetchAQICN(fetcher: Fetcher, token: string | undefined, location: Location): Promise<unknown> {
  if (!token?.trim()) throw new SourceError('not_configured');
  const url = new URL(`https://api.waqi.info/feed/geo:${location.latitude};${location.longitude}/`);
  url.searchParams.set('token', token);
  const response = await fetcher(url, { signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new SourceError('unavailable');
  return response.json();
}
export function decodeAQICN(payload: unknown, location: Location, now: number, radius: number, maxAge: number): Observation {
  const root = record(payload), data = record(root.data), city = record(data.city), time = record(data.time);
  const value = nonnegative(data.aqi), geo = city.geo;
  const iso = typeof time.iso === 'string' && /(?:Z|[+-]\d{2}:\d{2})$/.test(time.iso) ? time.iso : '';
  const observed = Date.parse(iso);
  if (root.status !== 'ok' || value === null || !Array.isArray(geo) || !coordinates(geo[0], geo[1])
    || typeof city.name !== 'string' || !Number.isSafeInteger(data.idx)
    || !usableTime(observed, now, maxAge)) throw new SourceError('no_usable_station');
  const km = distance(location, geo[0], geo[1]);
  if (km > radius) throw new SourceError('no_usable_station');
  const attribution = (Array.isArray(data.attributions) ? data.attributions : []).flatMap(item => {
    const a = record(item);
    if (typeof a.name !== 'string' || typeof a.url !== 'string') return [];
    try { if (!['http:', 'https:'].includes(new URL(a.url).protocol)) return []; } catch { return []; }
    return [{ name: a.name, url: a.url }];
  });
  if (!attribution.length) throw new SourceError('unavailable');
  if (!attribution.some(a => /waqi\.info|aqicn\.org/.test(new URL(a.url).hostname)))
    attribution.push({ name: 'World Air Quality Index Project', url: 'https://aqicn.org/' });
  const pm25 = nonnegative(record(record(data.iaqi).pm25).v);
  const rounded = Math.round(value);
  return { source: 'aqicn', index: { value: rounded, scale: 'AQICN_AQI', metric: 'overall', category: category(rounded, false) },
    pm25_index: pm25 === null ? null : { value: Math.round(pm25), scale: 'AQICN_AQI', metric: 'pm25' },
    pm25_24h_concentration: null,
    station: { id: String(data.idx), name: city.name, latitude: geo[0], longitude: geo[1], distance_km: km },
    observed_at: new Date(observed).toISOString(), fetched_at: new Date(now).toISOString(), attribution };
}
