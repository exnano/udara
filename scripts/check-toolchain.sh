#!/bin/bash
set -euo pipefail
if [[ "$(xcodebuild -version | head -n 1)" != 'Xcode 27.0' ]]; then
    echo 'This release requires Xcode 27.0. Set DEVELOPER_DIR to its Developer directory.' >&2
    exit 1
fi
