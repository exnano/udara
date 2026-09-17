import { SourceError, type Fetcher, type Location, type Observation } from '../types';
import { category, coordinates, distance, nonnegative, record } from '../validation';
export async function fetchOpenMeteo(fetcher: Fetcher, location: Location): Promise<unknown> {
  const url = new URL('https://air-quality-api.open-meteo.com/v1/air-quality');
  url.search = new URLSearchParams({ latitude: String(location.latitude), longitude: String(location.longitude), hourly: 'us_aqi,us_aqi_pm2_5', forecast_days: '1', timezone: 'GMT', timeformat: 'unixtime' }).toString();
  const response = await fetcher(url, { signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new SourceError('unavailable');
  return response.json();
}
export function decodeOpenMeteo(payload: unknown, location: Location, now: number): Observation {
  const root = record(payload), hourly = record(root.hourly);
  const times = hourly.time, overall = hourly.us_aqi, pm = hourly.us_aqi_pm2_5;
  if (root.error || !coordinates(root.latitude, root.longitude) || !Array.isArray(times) || !Array.isArray(overall) || !Array.isArray(pm)
    || times.length !== overall.length || times.length !== pm.length || times.length > 168
    || times.some((t, i) => typeof t !== 'number' || !Number.isFinite(t) || (i > 0 && t <= times[i - 1]))) throw new SourceError('unavailable');
  const hour = Math.floor(now / 3600_000) * 3600;
  const i = times.indexOf(hour);
  const value = nonnegative(overall[i]), pm25 = nonnegative(pm[i]);
  if (i < 0 || value === null || pm25 === null) throw new SourceError('no_usable_station');
  return { source: 'open_meteo', index: { value: Math.round(value), scale: 'US_AQI', metric: 'overall', category: category(Math.round(value), false) },
    pm25_index: { value: Math.round(pm25), scale: 'US_AQI', metric: 'pm25' }, pm25_24h_concentration: null,
    station: { id: `grid:${root.latitude}:${root.longitude}`, name: 'Model grid', latitude: root.latitude, longitude: root.longitude as number, distance_km: distance(location, root.latitude, root.longitude as number) },
    observed_at: new Date(hour * 1000).toISOString(), fetched_at: new Date(now).toISOString(),
    attribution: [{ name: 'Open-Meteo', url: 'https://open-meteo.com/' }, { name: 'CAMS', url: 'https://atmosphere.copernicus.eu/' }] };
}
