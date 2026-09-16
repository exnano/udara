import importlib.util
from datetime import datetime, timezone
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('waqi_assessment', ROOT / 'scripts/assess-waqi.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WAQIAssessmentTests(unittest.TestCase):
    def payload(self, value=55):
        return {'status': 'ok', 'data': {'idx': 123, 'aqi': value, 'city': {'name': 'Fixture station', 'geo': [3.14, 101.69]}, 'time': {'iso': '2026-09-16T18:00:00+08:00'}}}

    def summarize(self, payload):
        return module.summarize(payload, 'Fixture city', 3.14, 101.69, datetime(2026, 9, 16, 11, tzinfo=timezone.utc))

    def test_observation_age_uses_offset_and_station_identity(self):
        result = self.summarize(self.payload())
        self.assertEqual(result['observation_age_hours'], 1)
        self.assertEqual(result['station_distance_km'], 0)
        self.assertEqual(result['station_id'], 123)
        self.assertEqual(result['waqi_aqi'], 55)

    def test_invalid_readings_are_not_zero(self):
        for value in ['-', None, -1, 'nan', 'inf']:
            self.assertIsNone(self.summarize(self.payload(value))['waqi_aqi'])

    def test_unknown_timestamp_is_not_assumed_fresh(self):
        payload = self.payload(); payload['data']['time'] = {'iso': '2026-09-16T18:00:00'}
        self.assertIsNone(self.summarize(payload)['observation_age_hours'])

    def test_api_errors_do_not_echo_server_secrets(self):
        with self.assertRaisesRegex(RuntimeError, 'Invalid key'):
            self.summarize({'status': 'error', 'data': 'Invalid key'})
        with self.assertRaises(RuntimeError) as result:
            self.summarize({'status': 'error', 'data': 'url?token=secret'})
        self.assertNotIn('secret', str(result.exception))
