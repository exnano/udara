#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RELEASE_VERSION:?Set RELEASE_VERSION}"
: "${GITHUB_REPOSITORY:?Set owner/repository}"
: "${RELEASE_NOTES_FILE:?Set the path to reviewed release notes}"
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
output="build/releases/$RELEASE_VERSION"
[[ -f "$RELEASE_NOTES_FILE" ]] || { echo 'Release notes file missing.' >&2; exit 1; }
(cd "$output" && shasum -a 256 -c SHA256SUMS)
gh release create "v$RELEASE_VERSION" --repo "$GITHUB_REPOSITORY" --verify-tag --draft \
    --title "Udara $RELEASE_VERSION" --notes-file "$RELEASE_NOTES_FILE" \
    "$output/Udara-$RELEASE_VERSION-universal.dmg" "$output/SHA256SUMS"
