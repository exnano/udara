#!/usr/bin/env python3
"""Local WAQI freshness/coverage comparison. Reads .env; never prints request URLs or tokens."""
import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen

from release_env import ROOT, load_dotenv

DEFAULT_CITIES = [
    ('Kuala Lumpur', 3.139, 101.6869),
    ('Petaling Jaya', 3.11, 101.61),
    ('Shah Alam', 3.0738, 101.5183),
    ('George Town', 5.4141, 100.3288),
]


def fetch(host, path, parameters):
    try:
        with urlopen('https://' + host + path + '?' + urlencode(parameters), timeout=25) as response:
            return json.load(response)
    except HTTPError as error:
        raise RuntimeError(f'{host}: HTTP {error.code}') from None
    except (URLError, TimeoutError, ValueError, OSError):
        raise RuntimeError(f'{host}: request failed (network or invalid JSON)') from None


def distance_km(latitude, longitude, coordinates):
    if not isinstance(coordinates, list) or len(coordinates) != 2:
        return None
    try:
        lat2, lon2 = map(float, coordinates)
        if not (-90 <= lat2 <= 90 and -180 <= lon2 <= 180):
            return None
        a, b = map(math.radians, [latitude, lat2])
        delta = math.radians(lon2 - longitude)
        h = math.sin((b-a)/2)**2 + math.cos(a)*math.cos(b)*math.sin(delta/2)**2
        return round(6371 * 2 * math.asin(math.sqrt(min(1, max(0, h)))), 1)
    except (TypeError, ValueError):
        return None


def summarize(payload, name, latitude, longitude, now):
    if payload.get('status') != 'ok':
        # Do not echo arbitrary server text; it could include a credential-bearing URL.
        if str(payload.get('data', '')).lower() in ('invalid key', 'unknown token', 'invalid token'):
            raise RuntimeError('WAQI rejected WAQI_TOKEN: Invalid key. Activate/check it and update .env.')
        raise RuntimeError('WAQI returned an API error; no observation available.')
    data = payload.get('data')
    if not isinstance(data, dict):
        raise RuntimeError('WAQI response has no observation object.')
    clock = data.get('time', {})
    stamp = clock.get('iso') or (str(clock.get('s', '')) + str(clock.get('tz', '')))
    age = None
    try:
        reported = datetime.fromisoformat(stamp)
        if reported.utcoffset() is not None:
            age = round((now - reported).total_seconds() / 3600, 2)
    except (ValueError, TypeError):
        pass
    raw = data.get('aqi')
    try:
        value = float(raw)
        value = value if math.isfinite(value) and value >= 0 else None
    except (TypeError, ValueError):
        value = None
    station = data.get('city', {})
    return {
        'query': name, 'station': station.get('name'), 'station_id': data.get('idx'),
        'station_distance_km': distance_km(latitude, longitude, station.get('geo')),
        'waqi_aqi': value, 'reported_at': stamp or None, 'observation_age_hours': age,
        'dominant_pollutant': data.get('dominentpol'),
        'station_url': station.get('url'),
        'attributions': data.get('attributions', []),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--city', nargs=3, action='append', metavar=('NAME', 'LAT', 'LON'))
    parser.add_argument('--compare-open-meteo', action='store_true', help='Also fetch the model-derived current-hour US AQI; differences do not prove accuracy.')
    args = parser.parse_args()
    # Deliberately read this local assessment credential from .env, not a bundled app or Keychain.
    settings = {}
    load_dotenv(ROOT / '.env', settings)
    token = settings.get('WAQI_TOKEN', '').strip()
    if not token:
        raise RuntimeError('Set WAQI_TOKEN in the ignored project .env first.')
    cities = args.city or DEFAULT_CITIES
    now = datetime.now(timezone.utc)
    print('Assessment UTC:', now.isoformat())
    print('Station observations and model forecasts are different products; compare reporting age and station distance, not just AQI numbers.')
    for name, latitude, longitude in cities:
        latitude, longitude = float(latitude), float(longitude)
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            raise RuntimeError('City coordinates are out of range.')
        payload = fetch('api.waqi.info', f'/feed/geo:{latitude};{longitude}/', {'token': token})
        summary = summarize(payload, name, latitude, longitude, now)
        if args.compare_open_meteo:
            model = fetch('air-quality-api.open-meteo.com', '/v1/air-quality', {
                'latitude': latitude, 'longitude': longitude, 'hourly': 'us_aqi',
                'forecast_days': 1, 'timezone': 'GMT', 'timeformat': 'unixtime',
            }).get('hourly', {})
            hour = int(now.timestamp() // 3600) * 3600
            summary['open_meteo_model_us_aqi'] = next((value for stamp, value in zip(model.get('time', []), model.get('us_aqi', [])) if stamp == hour), None)
        # Redact defensively even if the service unexpectedly reflects the token in a field.
        print(json.dumps(summary, ensure_ascii=False).replace(token, '[redacted]'))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
