#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
python3 -m unittest discover -s Tests/ReleaseToolingTests -v
xcodebuild -project Udara.xcodeproj -scheme Udara -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData test "$@"
