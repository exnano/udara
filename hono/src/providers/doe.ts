import { SourceError, type Fetcher, type Location, type Observation } from '../types';
import { category, coordinates, distance, nonnegative, record, usableTime } from '../validation';
export const DOE_ENDPOINT = 'https://eqms.doe.gov.my/api3/publicmapproxy/PUBLIC_DISPLAY/CAQM_MCAQM_Current_Reading/MapServer/0/query';
// Never request operational contact fields or trust the rounded ArcGIS geometry.
const fields = ['STATION_ID', 'DATETIME', 'API', 'SI_PM25', 'PM25_24H_AVG', 'FLAG_PM25AVG',
  'LATITUDE', 'LONGITUDE', 'STATION_LOCATION', 'STATION_STATUS'];
export function doeURL(): string {
  const url = new URL(DOE_ENDPOINT);
  url.search = new URLSearchParams({ f: 'json', where: '1=1', outFields: fields.join(','), returnGeometry: 'false' }).toString();
  return url.toString();
}
export function decodeDOE(payload: unknown, location: Location, now: number, fetchedAt: string, radius: number, maxAge: number, requirePM25 = false): Observation {
  const root = record(payload);
  if (root.error || root.exceededTransferLimit || !Array.isArray(root.features)) throw new SourceError('unavailable');
  const candidates: Observation[] = [];
  for (const feature of root.features) {
    const a = record(record(feature).attributes);
    const api = nonnegative(a.API);
    if (a.STATION_STATUS !== 1 || api === null || !coordinates(a.LATITUDE, a.LONGITUDE)
      || typeof a.STATION_ID !== 'string' || typeof a.STATION_LOCATION !== 'string' || typeof a.DATETIME !== 'number') continue;
    // This DOE layer encodes MY wall-clock components as UTC milliseconds.
    // Verified against DOE portal display and same-station AQICN ISO timestamp.
    const observed = a.DATETIME - 8 * 3600_000;
    const km = distance(location, a.LATITUDE, a.LONGITUDE as number);
    if (!usableTime(observed, now, maxAge) || km > radius) continue;
    const pm25 = a.FLAG_PM25AVG == null || a.FLAG_PM25AVG === '' ? nonnegative(a.SI_PM25) : null;
    if (requirePM25 && pm25 === null) continue;
    const concentration = pm25 !== null ? nonnegative(a.PM25_24H_AVG) : null;
    const value = Math.round(api);
    candidates.push({ source: 'doe', index: { value, scale: 'MY_API', metric: 'overall', category: category(value, true) },
      pm25_index: pm25 === null ? null : { value: Math.round(pm25), scale: 'MY_API', metric: 'pm25' },
      pm25_24h_concentration: concentration === null ? null : { value: concentration, unit: 'µg/m³', averaging_period: '24h' },
      station: { id: a.STATION_ID, name: a.STATION_LOCATION, latitude: a.LATITUDE, longitude: a.LONGITUDE as number, distance_km: km },
      observed_at: new Date(observed).toISOString(), fetched_at: fetchedAt,
      attribution: [{ name: 'Department of Environment Malaysia', url: 'https://eqms.doe.gov.my/' }] });
  }
  candidates.sort((a, b) => a.station.distance_km - b.station.distance_km || a.station.id.localeCompare(b.station.id));
  if (!candidates.length) throw new SourceError('no_usable_station');
  return candidates[0];
}
export async function fetchDOE(fetcher: Fetcher): Promise<unknown> {
  const response = await fetcher(doeURL(), { signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new SourceError('unavailable');
  return response.json();
}
