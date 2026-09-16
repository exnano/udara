#!/bin/bash
set -euo pipefail
cd -P "$(dirname "$0")/.."
if [[ "${UDARA_ENV_LOADED:-}" != "$PWD" ]]; then
    exec python3 scripts/release_env.py -- /bin/bash scripts/create-draft-release.sh "$@"
fi
python3 scripts/version.py check
RELEASE_VERSION="$(python3 scripts/version.py show --field version)"
: "${GITHUB_REPOSITORY:?Set owner/repository}"
: "${RELEASE_NOTES_FILE:?Set the path to reviewed release notes}"
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
output="build/releases/$RELEASE_VERSION"
[[ -f "$RELEASE_NOTES_FILE" ]] || { echo 'Release notes file missing.' >&2; exit 1; }
(cd "$output" && shasum -a 256 -c SHA256SUMS)
gh release create "v$RELEASE_VERSION" --repo "$GITHUB_REPOSITORY" --verify-tag --draft \
    --title "Udara $RELEASE_VERSION" --notes-file "$RELEASE_NOTES_FILE" \
    "$output/Udara-$RELEASE_VERSION-universal.dmg" "$output/SHA256SUMS"
