#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh Debug
app="$PWD/build/DerivedData/Build/Products/Debug/Udara.app"
# Only stop the exact executable built in this checkout.
pkill -f "^${app}/Contents/MacOS/Udara([[:space:]]|$)" || true
open "$app" --args "$@"
