export type Bindings = {
  WAQI_TOKEN?: string;
  AQICN_RADIUS_KM?: string;
  DOE_RADIUS_KM?: string;
  MAX_OBSERVATION_AGE_SECONDS?: string;
};
export type Location = { latitude: number; longitude: number; country: string };
export type Observation = {
  source: 'doe' | 'aqicn';
  index: { value: number; scale: 'MY_API' | 'AQICN_AQI'; metric: 'overall'; category: string };
  pm25_index: { value: number; scale: 'MY_API' | 'AQICN_AQI'; metric: 'pm25' } | null;
  pm25_24h_concentration: { value: number; unit: 'µg/m³'; averaging_period: '24h' } | null;
  station: { id: string; name: string; latitude: number; longitude: number; distance_km: number };
  observed_at: string;
  fetched_at: string;
  attribution: { name: string; url: string }[];
};
export type Fetcher = (url: string | URL, init?: RequestInit) => Promise<Response>;
export class SourceError extends Error {
  constructor(public reason: 'unavailable' | 'no_usable_station' | 'not_configured') {
    super(reason);
  }
}
