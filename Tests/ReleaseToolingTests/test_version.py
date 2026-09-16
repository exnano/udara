import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/version.py'

class VersionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.file = Path(self.directory.name) / 'Version.xcconfig'
        self.file.write_text('// Preserve comments\nMARKETING_VERSION = 1.2.3\nCURRENT_PROJECT_VERSION = 8\n')

    def run_command(self, *args, **overrides):
        env = dict(os.environ)
        env.pop('RELEASE_VERSION', None); env.pop('BUILD_NUMBER', None)
        env.update(overrides)
        return subprocess.run(['python3', str(SCRIPT), '--file', str(self.file), *args], env=env, capture_output=True, text=True)

    def test_show(self):
        result = self.run_command('show')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {'version': '1.2.3', 'build': 8, 'tag': 'v1.2.3'})

    def test_bumps_reset_lower_components_and_increment_build(self):
        for part, expected in [('patch', '1.2.4'), ('minor', '1.3.0'), ('major', '2.0.0'), ('build', '1.2.3')]:
            with self.subTest(part=part):
                self.setUp()
                result = self.run_command('bump', part)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)['version'], expected)
                self.assertEqual(json.loads(result.stdout)['build'], 9)
                self.assertIn('// Preserve comments', self.file.read_text())

    def test_dry_run_does_not_write(self):
        original = self.file.read_bytes()
        result = self.run_command('bump', 'minor', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['version'], '1.3.0')
        self.assertEqual(self.file.read_bytes(), original)

    def test_matching_release_expectations(self):
        self.assertEqual(self.run_command('check', RELEASE_VERSION='1.2.3', BUILD_NUMBER='8').returncode, 0)

    def test_mismatched_release_expectations_are_rejected(self):
        for env in [dict(RELEASE_VERSION='1.2.4'), dict(BUILD_NUMBER='9'), dict(RELEASE_VERSION='v1.2.3')]:
            self.assertNotEqual(self.run_command('check', **env).returncode, 0)

    def test_invalid_or_duplicate_settings_fail_without_writing(self):
        for text in ['MARKETING_VERSION = 01.2.3\nCURRENT_PROJECT_VERSION = 8\n',
                     'MARKETING_VERSION = 1.2.3-beta\nCURRENT_PROJECT_VERSION = 8\n',
                     'MARKETING_VERSION = 1.2.3\nCURRENT_PROJECT_VERSION = 0\n',
                     'MARKETING_VERSION = 1.2.3\nCURRENT_PROJECT_VERSION = 8\nCURRENT_PROJECT_VERSION = 9\n',
                     'MARKETING_VERSION = 1.2.3\n#include "Elsewhere.xcconfig"\nCURRENT_PROJECT_VERSION = 8\n']:
            self.file.write_text(text)
            self.assertNotEqual(self.run_command('bump', 'patch').returncode, 0)
            self.assertEqual(self.file.read_text(), text)

    def test_verify_artifact_detects_stale_bundle(self):
        import plistlib
        plist = Path(self.directory.name) / 'Info.plist'
        plist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '8'}))
        self.assertEqual(self.run_command('verify-plist', str(plist)).returncode, 0)
        plist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.2.2', 'CFBundleVersion': '8'}))
        self.assertNotEqual(self.run_command('verify-plist', str(plist)).returncode, 0)

if __name__ == '__main__': unittest.main()
