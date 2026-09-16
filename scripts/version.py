#!/usr/bin/env python3
"""Read, validate, and atomically bump Udara's shared Xcode version settings."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import tempfile

DEFAULT_FILE = Path(__file__).resolve().parents[1] / 'Config/Version.xcconfig'
VERSION_PATTERN = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'


def read_version(path=DEFAULT_FILE):
    settings = {}
    for line in path.read_text().splitlines():
        line = line.split('//', 1)[0].strip()
        if not line:
            continue
        match = re.fullmatch(r'(MARKETING_VERSION|CURRENT_PROJECT_VERSION)\s*=\s*(\S+)', line)
        if not match or match[1] in settings:
            raise ValueError('Version.xcconfig must contain exactly one assignment for each version setting and no includes/overrides.')
        settings[match[1]] = match[2]
    version = settings.get('MARKETING_VERSION', '')
    build = settings.get('CURRENT_PROJECT_VERSION', '')
    if not re.fullmatch(VERSION_PATTERN, version) or not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Expected a stable MAJOR.MINOR.PATCH version and a positive integer build, without leading zeros.')
    return {'version': version, 'build': int(build), 'tag': f'v{version}'}


def check_expectations(value):
    for key, expected in [('RELEASE_VERSION', value['version']), ('BUILD_NUMBER', str(value['build']))]:
        if key in os.environ and os.environ[key] != expected:
            raise ValueError(f'{key} does not match Config/Version.xcconfig ({expected}). Check out the intended release tag or unset the override.')


def release_version():
    """Shared guard for release tools; environment values are assertions, not overrides."""
    value = read_version()
    check_expectations(value)
    return value


def bump(path, part, dry_run=False):
    value = read_version(path)
    numbers = [int(number) for number in value['version'].split('.')]
    if part != 'build':
        index = ['major', 'minor', 'patch'].index(part)
        numbers[index] += 1
        numbers[index + 1:] = [0] * (2 - index)
    version = '.'.join(map(str, numbers))
    result = {'version': version, 'build': value['build'] + 1, 'tag': f'v{version}'}
    if not dry_run:
        text = path.read_text()
        for key, new in [('MARKETING_VERSION', result['version']), ('CURRENT_PROJECT_VERSION', result['build'])]:
            text = re.sub(rf'(?m)^(\s*{key}\s*=\s*)\S+', lambda match: match[1] + str(new), text)
        # Replace the single source atomically; keep existing comments and permissions.
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.version-', delete=False) as handle:
                temporary = Path(handle.name)
                handle.write(text)
                handle.flush()
                os.fsync(handle.fileno())
            temporary.chmod(path.stat().st_mode & 0o777)
            temporary.replace(path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--file', type=Path, default=DEFAULT_FILE, help='Alternative config for tests or another checkout')
    commands = parser.add_subparsers(dest='command', required=True)
    show = commands.add_parser('show', help='Print the current version as JSON or a single field')
    show.add_argument('--field', choices=['version', 'build', 'tag'])
    commands.add_parser('check', help='Validate the config and any release environment expectations')
    update = commands.add_parser('bump', help='Increment the selected component and always increment the build')
    update.add_argument('part', choices=['patch', 'minor', 'major', 'build'])
    update.add_argument('--dry-run', action='store_true')
    verify = commands.add_parser('verify-plist', help='Require an app Info.plist to match the source version')
    verify.add_argument('plist', type=Path)
    args = parser.parse_args()
    try:
        value = read_version(args.file)
        if args.command == 'bump':
            value = bump(args.file, args.part, args.dry_run)
        elif args.command in ('check', 'verify-plist'):
            check_expectations(value)
            if args.command == 'verify-plist':
                info = plistlib.loads(args.plist.read_bytes())
                if info.get('CFBundleShortVersionString') != value['version'] or info.get('CFBundleVersion') != str(value['build']):
                    raise ValueError('Built app version/build does not match Config/Version.xcconfig.')
        print(value[args.field] if args.command == 'show' and args.field else json.dumps(value))
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        parser.exit(1, f'Version error: {error}\n')


if __name__ == '__main__':
    main()
