#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
[[ "$configuration" == Debug || "$configuration" == Release ]] || { echo 'Usage: scripts/build.sh [Debug|Release]' >&2; exit 2; }
xcodebuild -project Udara.xcodeproj -scheme Udara -configuration "$configuration" -derivedDataPath build/DerivedData build
