import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_env', ROOT / 'scripts/release_env.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseEnvironmentTests(unittest.TestCase):
    def load(self, content, initial=None):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / '.env'
            path.write_text(content)
            env = dict(initial or {})
            module.load_dotenv(path, env)
            return env

    def test_quotes_export_comments_and_crlf(self):
        env = self.load("# local\r\nexport APPLE_TEAM_ID=6G94876K55\r\nSIGNING_IDENTITY='Developer ID Application: Example (6G94876K55)' # comment\nEMPTY=\nHASH=\"a#b\"\n")
        self.assertEqual(env['SIGNING_IDENTITY'], 'Developer ID Application: Example (6G94876K55)')
        self.assertEqual(env['APPLE_TEAM_ID'], '6G94876K55')
        self.assertEqual(env['EMPTY'], '')
        self.assertEqual(env['HASH'], 'a#b')

    def test_exported_values_win_including_empty(self):
        self.assertEqual(self.load('A=file\nB=file\n', {'A': 'ci', 'B': ''}), {'A': 'ci', 'B': ''})

    def test_shell_syntax_is_literal(self):
        self.assertEqual(self.load("VALUE='$(touch /tmp/should-not-run) $HOME `whoami`'\n")['VALUE'], '$(touch /tmp/should-not-run) $HOME `whoami`')

    def test_invalid_input_does_not_partially_load_or_echo_values(self):
        for content in ['A=valid\nBAD LINE secret-value', "A=valid\nB='secret-value", 'A=valid\nB=secret value']:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / '.env'; path.write_text(content)
                env = {}
                with self.assertRaises(ValueError) as failure:
                    module.load_dotenv(path, env)
                self.assertEqual(env, {})
                self.assertNotIn('secret', str(failure.exception))

    def test_missing_file_is_optional(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {'A': 'ci'}
            module.load_dotenv(Path(directory) / '.env', env)
            self.assertEqual(env, {'A': 'ci'})

    def test_shell_entrypoints_load_before_release_checks_from_any_directory(self):
        for script in ['release.sh', 'create-draft-release.sh']:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as directory:
                project = Path(directory) / 'project'
                (project / 'scripts').mkdir(parents=True)
                for name in [script, 'release_env.py']:
                    shutil.copy2(ROOT / 'scripts' / name, project / 'scripts' / name)
                # Stop at the first version check, before build, signing or publication.
                (project / 'scripts/version.py').write_text('import os,sys\nassert os.environ["NOTARY_PROFILE"] == "from-dotenv"\nsys.exit(73)\n')
                (project / '.env').write_text('NOTARY_PROFILE=from-dotenv\n')
                env = dict(os.environ)
                env.pop('NOTARY_PROFILE', None); env.pop('UDARA_ENV_LOADED', None)
                result = subprocess.run(['/bin/bash', str(project / 'scripts' / script)], cwd=directory, env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 73, result.stderr)
