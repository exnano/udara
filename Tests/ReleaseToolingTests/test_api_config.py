import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('api_config', ROOT / 'scripts/configure-api.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class APIConfigTests(unittest.TestCase):
    def test_localhost_is_development_only(self):
        self.assertEqual(module.validate_url('http://localhost:8787/', True), 'http://localhost:8787')
        with self.assertRaises(ValueError): module.validate_url('http://localhost:8787')

    def test_production_requires_https_without_secrets_or_config_injection(self):
        self.assertEqual(module.validate_url('https://api.example.com'), 'https://api.example.com')
        for url in ['http://example.com', 'https://user:pass@example.com', 'https://example.com?token=x', 'https://example.com\nEVIL=YES', 'https://example.com/$(EVIL)']:
            with self.subTest(url=url), self.assertRaises(ValueError): module.validate_url(url)
