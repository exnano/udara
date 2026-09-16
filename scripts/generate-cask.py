#!/usr/bin/env python3
"""Generate a cask only after verifying the published GitHub release asset."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from version import release_version
from release_env import load_dotenv

try:
    load_dotenv()
except (OSError, ValueError) as error:
    raise SystemExit(f'Release environment error: {error}') from None

def required(name, pattern):
    value = os.environ.get(name, '')
    if not re.fullmatch(pattern, value):
        raise SystemExit(f'Missing or invalid {name}')
    return value

try:
    version = release_version()['version']
except (OSError, ValueError) as error:
    raise SystemExit(f'Version error: {error}')
repo = required('GITHUB_REPOSITORY', r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+')
bundle = required('UDARA_BUNDLE_ID', r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+')
if bundle.startswith('local.'):
    raise SystemExit('A production bundle identifier is required')
visibility = json.loads(subprocess.check_output(['gh', 'repo', 'view', repo, '--json', 'visibility']))
if visibility['visibility'] != 'PUBLIC':
    raise SystemExit('Homebrew distribution requires a public repository')
release = json.loads(subprocess.check_output(['gh', 'release', 'view', f'v{version}', '--repo', repo, '--json', 'isDraft,isPrerelease']))
if release['isDraft'] or release['isPrerelease']:
    raise SystemExit('Publish a stable release before updating the cask')
filename = f'Udara-{version}-universal.dmg'
with tempfile.TemporaryDirectory(prefix='udara-cask-') as directory:
    subprocess.run(['gh', 'release', 'download', f'v{version}', '--repo', repo, '--pattern', filename, '--pattern', 'SHA256SUMS', '--dir', directory], check=True)
    checksum = hashlib.sha256((Path(directory) / filename).read_bytes()).hexdigest()
    lines = (Path(directory) / 'SHA256SUMS').read_text().splitlines()
    if not any(line.split() == [checksum, filename] for line in lines):
        raise SystemExit('Published checksum does not match DMG')
print(f'''cask "udara" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/{repo}/releases/download/v#{{version}}/Udara-#{{version}}-universal.dmg"
  name "Udara"
  desc "Menu bar air quality estimates for your cities"
  homepage "https://github.com/{repo}"

  depends_on macos: ">= :tahoe"

  app "Udara.app"

  zap trash: [
    "~/Library/Containers/{bundle}",
    "~/Library/Application Support/Udara",
    "~/Library/Preferences/{bundle}.plist",
  ]
end''')
