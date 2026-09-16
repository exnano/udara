import hashlib
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FAKE_GH = '''#!/usr/bin/env python3
import hashlib,json,os,pathlib,sys
args=sys.argv[1:]
if args[:2] == ['repo','view']:
    print(json.dumps({'visibility':os.environ.get('VISIBILITY','PUBLIC')}))
elif args[:2] == ['release','view']:
    print(json.dumps({'isDraft':os.environ.get('DRAFT')=='1','isPrerelease':False}))
elif args[:2] == ['release','download']:
    dest=pathlib.Path(args[args.index('--dir')+1]); data=b'test artifact'
    name='Udara-1.0.0-universal.dmg'
    (dest/name).write_bytes(data)
    sha='bad' if os.environ.get('BAD_HASH') else hashlib.sha256(data).hexdigest()
    (dest/'SHA256SUMS').write_text(sha+'  '+name+'\\n')
else:
    sys.exit(4)
'''

class CaskTests(unittest.TestCase):
    def run_generator(self, dotenv=None, **overrides):
        with tempfile.TemporaryDirectory() as directory:
            gh = Path(directory) / 'gh'; gh.write_text(FAKE_GH); gh.chmod(0o755)
            project = Path(directory) / 'project'
            (project / 'scripts').mkdir(parents=True)
            (project / 'Config').mkdir()
            (project / 'Config/Version.xcconfig').write_text('MARKETING_VERSION = 1.0.0\nCURRENT_PROJECT_VERSION = 1\n')
            for name in ['generate-cask.py', 'version.py', 'release_env.py']:
                shutil.copy2(ROOT / 'scripts' / name, project / 'scripts' / name)
            env = dict(os.environ, PATH=f'{directory}:{os.environ["PATH"]}', RELEASE_VERSION='1.0.0', GITHUB_REPOSITORY='example/udara', UDARA_BUNDLE_ID='org.example.udara')
            env.pop('BUILD_NUMBER', None)
            if dotenv is not None:
                (project / '.env').write_text(dotenv)
                env.pop('GITHUB_REPOSITORY', None)
                env.pop('UDARA_BUNDLE_ID', None)
            env.update(overrides)
            return subprocess.run([str(project/'scripts/generate-cask.py')], env=env, capture_output=True, text=True)
    def test_public_artifact_hash_and_preserved_preferences(self):
        result = self.run_generator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(hashlib.sha256(b'test artifact').hexdigest(), result.stdout)
        self.assertIn('zap trash:', result.stdout)
        self.assertNotIn('uninstall delete:', result.stdout)
    def test_release_identity_can_come_from_dotenv(self):
        result = self.run_generator(dotenv='GITHUB_REPOSITORY=example/udara\nUDARA_BUNDLE_ID=org.example.udara\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('https://github.com/example/udara', result.stdout)

    def test_version_mismatch_is_rejected_before_gh(self):
        self.assertNotEqual(self.run_generator(RELEASE_VERSION='1.0.1').returncode, 0)

    def test_draft_is_rejected(self):
        self.assertNotEqual(self.run_generator(DRAFT='1').returncode, 0)
    def test_private_repository_is_rejected(self):
        self.assertNotEqual(self.run_generator(VISIBILITY='PRIVATE').returncode, 0)
    def test_checksum_mismatch_is_rejected(self):
        self.assertNotEqual(self.run_generator(BAD_HASH='1').returncode, 0)
    def test_untrusted_repository_shape_is_rejected(self):
        self.assertNotEqual(self.run_generator(GITHUB_REPOSITORY='owner/repo;echo bad').returncode, 0)

if __name__ == '__main__': unittest.main()
