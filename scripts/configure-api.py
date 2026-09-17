#!/usr/bin/env python3
"""Generate URL-only Xcode settings from ignored .env; never copy secrets."""
import argparse
import os
from pathlib import Path
from urllib.parse import urlsplit
from release_env import load_dotenv, ROOT


def validate_url(value, development=False):
    try:
        url = urlsplit(value)
        local = url.hostname in ('localhost', '127.0.0.1', '::1')
        valid = url.scheme == 'https' and not local or development and url.scheme == 'http' and local
        if not valid or not url.hostname or url.username or url.password or url.query or url.fragment or any(c in value for c in '\r\n$#\\" '):
            raise ValueError()
        _ = url.port
    except ValueError:
        raise ValueError('API URL must be HTTPS (Debug also allows HTTP localhost), without credentials, query or fragment.') from None
    return value.rstrip('/')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('configuration', choices=['Debug', 'Release'], nargs='?', default='Debug')
    args = parser.parse_args()
    load_dotenv()
    debug = validate_url(os.environ.get('UDARA_API_URL_DEVELOPMENT', 'http://localhost:8787'), True)
    production = os.environ.get('UDARA_API_URL_PRODUCTION', '').strip()
    if production:
        production = validate_url(production)
    if args.configuration == 'Release' and not production:
        raise SystemExit('Set UDARA_API_URL_PRODUCTION to the deployed HTTPS backend in .env before a Release build.')
    # xcconfig interprets // as a comment. The empty expansion preserves URL slashes.
    escape = lambda value: value.replace('://', ':/$()/')
    text = '// Generated URL settings only. Do not edit.\n'
    text += f'UDARA_API_URL[config=Debug] = {escape(debug)}\n'
    text += f'UDARA_API_URL[config=Release] = {escape(production)}\n'
    (ROOT / 'Config/API.local.xcconfig').write_text(text)
    print(f'Configured {args.configuration} API URL settings (no credentials embedded).')

if __name__ == '__main__':
    main()
