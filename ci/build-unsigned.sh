#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build
build_number="${BUILD_NUMBER:-1}"

xcodebuild -version
xcodebuild \
  -project HelloFlight.xcodeproj \
  -scheme HelloFlight \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/HelloFlight.xcarchive \
  -derivedDataPath build/DerivedData \
  "CURRENT_PROJECT_VERSION=$build_number" \
  CODE_SIGNING_ALLOWED=NO \
  archive 2>&1 | tee build/xcodebuild.log

app_path="build/HelloFlight.xcarchive/Products/Applications/HelloFlight.app"
test -f "$app_path/HelloFlight"
file "$app_path/HelloFlight"
xcrun lipo "$app_path/HelloFlight" -verify_arch arm64
python3 - "$app_path/Info.plist" <<'PY'
import json
import plistlib
import sys

with open(sys.argv[1], 'rb') as stream:
    info = plistlib.load(stream)
assert info['CFBundleIdentifier'] == 'com.hority.helloflight', 'Unexpected bundle ID'
assert set(info['UIDeviceFamily']) == {1, 2}, 'Both iPhone and iPad must be supported'
assert info['ITSAppUsesNonExemptEncryption'] is False, 'Encryption declaration must be a boolean'
orientations = info.get('UISupportedInterfaceOrientations~ipad') or info.get('UISupportedInterfaceOrientations')
assert info.get('UISupportedInterfaceOrientations~iphone', info.get('UISupportedInterfaceOrientations')) == ['UIInterfaceOrientationPortrait'], 'The penguin game is portrait-only on iPhone'
assert set(orientations) == {
    'UIInterfaceOrientationPortrait',
    'UIInterfaceOrientationPortraitUpsideDown',
    'UIInterfaceOrientationLandscapeLeft',
    'UIInterfaceOrientationLandscapeRight',
}, 'iPad multitasking requires all four interface orientations'
icon = info['CFBundleIcons']['CFBundlePrimaryIcon']
assert icon['CFBundleIconName'] == 'AppIcon', 'App Store icon must be included'
print(json.dumps({
    'bundle_id': info['CFBundleIdentifier'],
    'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'],
    'minimum_ios': info['MinimumOSVersion'],
    'ipad_orientations': orientations,
    'iphone_orientations': info.get('UISupportedInterfaceOrientations~iphone', info.get('UISupportedInterfaceOrientations')),
    'encryption_declaration': info['ITSAppUsesNonExemptEncryption'],
    'app_icon': icon['CFBundleIconName'],
}, ensure_ascii=False, indent=2))
PY
ditto -c -k --sequesterRsrc --keepParent \
  build/HelloFlight.xcarchive build/HelloFlight-unsigned.xcarchive.zip

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
## iOS build succeeded

- App: HelloFlight
- Bundle ID: com.hority.helloflight
- Build: $build_number
- Architecture: iPhone / iPad (arm64)
- Signing: unsigned; this artifact cannot be installed on an iPhone.
- Distribution remains in the separate private release setup.
EOF
fi
