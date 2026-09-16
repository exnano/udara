#!/usr/bin/env python3
"""Load literal release settings from the project .env; never execute its contents."""
import os
from pathlib import Path
import re
import shlex
import sys

ROOT = Path(__file__).resolve().parents[1]


def load_dotenv(path=None, environ=None):
    path = Path(path) if path is not None else ROOT / '.env'
    environ = os.environ if environ is None else environ
    if not path.exists():
        return
    values = {}
    for number, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        match = re.fullmatch(r'(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)', line)
        if not match:
            raise ValueError(f'{path.name}:{number}: expected KEY=value')
        key, raw = match.groups()
        try:
            parts = shlex.split(raw, comments=True, posix=True)
        except ValueError:
            raise ValueError(f'{path.name}:{number}: invalid quoting') from None
        if len(parts) > 1:
            raise ValueError(f'{path.name}:{number}: quote values containing spaces')
        value = parts[0] if parts else ''
        if '\x00' in value:
            raise ValueError(f'{path.name}:{number}: invalid null character')
        values[key] = value
    # Parse fully before changing the environment. Existing exports, including empty ones, win.
    for key, value in values.items():
        environ.setdefault(key, value)


def main():
    command = sys.argv[1:]
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        raise SystemExit('Usage: release_env.py -- command [arguments...]')
    try:
        load_dotenv()
    except (OSError, ValueError) as error:
        raise SystemExit(f'Release environment error: {error}') from None
    os.environ['UDARA_ENV_LOADED'] = str(ROOT)
    os.execvp(command[0], command)


if __name__ == '__main__':
    main()
