import type { Location } from './types';
export const record = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
export const nonnegative = (value: unknown): number | null =>
  typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
export function coordinates(lat: unknown, lon: unknown): lat is number {
  return typeof lat === 'number' && typeof lon === 'number' && Number.isFinite(lat) && Number.isFinite(lon)
    && Math.abs(lat) <= 90 && Math.abs(lon) <= 180;
}
export function distance(location: Location, lat: number, lon: number): number {
  const rad = Math.PI / 180;
  const h = Math.sin((lat - location.latitude) * rad / 2) ** 2
    + Math.cos(location.latitude * rad) * Math.cos(lat * rad) * Math.sin((lon - location.longitude) * rad / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}
export function usableTime(time: number, now: number, maxAge: number): boolean {
  return Number.isFinite(time) && time <= now + 5 * 60_000 && now - time <= maxAge * 1000;
}
export function category(value: number, malaysia: boolean): string {
  if (value <= 50) return 'Good';
  if (value <= 100) return 'Moderate';
  if (!malaysia && value <= 150) return 'Unhealthy for sensitive groups';
  if (value <= 200) return 'Unhealthy';
  if (value <= 300) return 'Very unhealthy';
  return 'Hazardous';
}
export function positiveSetting(value: string | undefined, fallback: number, maximum: number): number {
  const parsed = value === undefined ? fallback : Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0 || parsed > maximum) throw new Error('Invalid server configuration');
  return parsed;
}
