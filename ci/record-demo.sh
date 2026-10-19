#!/bin/bash
# シミュレータで -demo の自動プレイを録画する（プロモ動画の素材用）。音声は録れない。
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build
duration="${DEMO_SECONDS:-80}"

udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in ds if d["name"].startswith("iPhone")]
pro = [d for d in devices if d["name"].endswith(" Pro")]
print((pro or devices)[-1]["udid"])')
xcrun simctl boot "$udid"

xcodebuild \
  -project HelloFlight.xcodeproj \
  -scheme HelloFlight \
  -configuration Debug \
  -destination "id=$udid" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build > build/xcodebuild.log 2>&1 || { tail -50 build/xcodebuild.log; exit 1; }

xcrun simctl bootstatus "$udid"
xcrun simctl install "$udid" build/DerivedData/Build/Products/Debug-iphonesimulator/HelloFlight.app
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3

xcrun simctl io "$udid" recordVideo --codec=h264 --force build/demo.mov &
recorder=$!
sleep 2
xcrun simctl launch "$udid" com.hority.helloflight -demo
sleep "$duration"
kill -INT "$recorder"
wait "$recorder" || true
test -s build/demo.mov
