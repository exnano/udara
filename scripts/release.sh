#!/bin/bash
# Produces verified local artifacts; does not upload or publish a release.
set -euo pipefail
cd "$(dirname "$0")/.."
for variable in UDARA_BUNDLE_ID APPLE_TEAM_ID SIGNING_IDENTITY NOTARY_PROFILE RELEASE_VERSION BUILD_NUMBER GITHUB_REPOSITORY; do
    [[ -n "${!variable:-}" ]] || { echo "Missing required release setting: $variable" >&2; exit 1; }
done
[[ "$UDARA_BUNDLE_ID" != local.* && "$UDARA_BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { echo 'Set a real reverse-domain bundle identifier.' >&2; exit 1; }
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid Apple Team ID.' >&2; exit 1; }
[[ "$SIGNING_IDENTITY" == 'Developer ID Application: '* ]] || { echo 'A Developer ID Application signing identity is required.' >&2; exit 1; }
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid version or build number.' >&2; exit 1; }
[[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'Invalid GitHub repository.' >&2; exit 1; }
./scripts/check-toolchain.sh
git diff --quiet && git diff --cached --quiet || { echo 'Release requires a clean checkout.' >&2; exit 1; }
[[ -z "$(git ls-files --others --exclude-standard)" ]] || { echo 'Release requires no untracked source files.' >&2; exit 1; }
[[ "$(git describe --tags --exact-match HEAD)" == "v$RELEASE_VERSION" ]] || { echo 'HEAD must match the release version tag.' >&2; exit 1; }
security find-identity -v -p codesigning | grep -F -- "$SIGNING_IDENTITY" >/dev/null || { echo 'Signing identity is not available in the keychain.' >&2; exit 1; }
./scripts/test.sh
output="$PWD/build/releases/$RELEASE_VERSION"
[[ ! -e "$output" ]] || { echo 'Release directory already exists; use a new version or archive the old build first.' >&2; exit 1; }
mkdir -p "$output"
archive="$output/Udara.xcarchive"
xcodebuild -project Udara.xcodeproj -scheme Udara -configuration Release -destination 'generic/platform=macOS' -archivePath "$archive" archive \
    "PRODUCT_BUNDLE_IDENTIFIER=$UDARA_BUNDLE_ID" "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" \
    "CODE_SIGN_IDENTITY=$SIGNING_IDENTITY" CODE_SIGN_STYLE=Manual \
    "MARKETING_VERSION=$RELEASE_VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO
export UDARA_RELEASE_OUTPUT="$output"
python3 - <<'PY'
import os, plistlib
from pathlib import Path
p=Path(os.environ['UDARA_RELEASE_OUTPUT'])/'ExportOptions.plist'
p.write_bytes(plistlib.dumps({'method':'developer-id','teamID':os.environ['APPLE_TEAM_ID'],'signingStyle':'manual','signingCertificate':os.environ['SIGNING_IDENTITY']}))
PY
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$output/export" -exportOptionsPlist "$output/ExportOptions.plist"
app="$output/export/Udara.app"
codesign --verify --deep --strict --verbose=2 "$app"
lipo "$app/Contents/MacOS/Udara" -verify_arch arm64 x86_64
codesign -dv --verbose=4 "$app" 2> "$output/app-signature.txt"
grep -q 'flags=.*runtime' "$output/app-signature.txt" || { echo 'Release app is missing Hardened Runtime.' >&2; exit 1; }
codesign -d --entitlements - "$app" > "$output/app-entitlements.plist" 2>/dev/null
python3 - "$output/app-entitlements.plist" "$app" <<'PYVERIFY'
import pathlib, plistlib, subprocess, sys
entitlements=plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
assert entitlements.get('com.apple.security.app-sandbox') is True, 'Sandbox is required'
assert entitlements.get('com.apple.security.network.client') is True, 'Outbound networking is required'
assert not entitlements.get('com.apple.security.get-task-allow', False), 'Debug entitlement in release'
for file in pathlib.Path(sys.argv[2]).rglob('*'):
    if file.is_file() and not file.is_symlink():
        with file.open('rb') as handle: magic=handle.read(4)
        if magic in [bytes.fromhex(v) for v in ['cffaedfe','feedfacf','cafebabe','bebafeca','cafebabf']]:
            subprocess.run(['lipo',str(file),'-verify_arch','arm64','x86_64'],check=True)
PYVERIFY
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist" | grep -Fx "$UDARA_BUNDLE_ID" >/dev/null
notarize() {
    local artifact="$1" label="$2"
    xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$output/$label-submission.json"
    local submission
    submission="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$output/$label-submission.json")"
    xcrun notarytool log "$submission" --keychain-profile "$NOTARY_PROFILE" "$output/$label-notary-log.json"
    python3 - "$output/$label-submission.json" "$output/$label-notary-log.json" <<'PY'
import json,sys
submission=json.load(open(sys.argv[1])); log=json.load(open(sys.argv[2]))
if submission.get('status') != 'Accepted': raise SystemExit('Notarization rejected; inspect the retained log.')
if log.get('issues'): raise SystemExit('Notarization log contains issues; review them before distributing.')
PY
}
ditto -c -k --keepParent "$app" "$output/Udara.zip"
notarize "$output/Udara.zip" app
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
staging="$output/dmg-root"
mkdir -p "$staging"
ditto "$app" "$staging/Udara.app"
ln -s /Applications "$staging/Applications"
dmg="$output/Udara-$RELEASE_VERSION-universal.dmg"
hdiutil create -volname Udara -srcfolder "$staging" -ov -format UDZO "$dmg"
codesign --sign "$SIGNING_IDENTITY" --timestamp "$dmg"
notarize "$dmg" dmg
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
mountpoint="$output/mounted"
mkdir -p "$mountpoint"
trap 'hdiutil detach "$mountpoint" >/dev/null 2>&1 || true' EXIT
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mountpoint"
codesign --verify --deep --strict --verbose=2 "$mountpoint/Udara.app"
xcrun stapler validate "$mountpoint/Udara.app"
lipo "$mountpoint/Udara.app/Contents/MacOS/Udara" -verify_arch arm64 x86_64
spctl --assess --type execute --verbose=2 "$mountpoint/Udara.app"
hdiutil detach "$mountpoint"
trap - EXIT
(cd "$output" && shasum -a 256 "$(basename "$dmg")" > SHA256SUMS)
printf 'Verified artifact: %s\n' "$dmg"
