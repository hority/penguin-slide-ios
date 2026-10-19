#!/bin/bash
# App Store用のスクリーンショットをシミュレータで撮る（6.9インチiPhoneと13インチiPad）。
# Debugビルドの撮影モード（PenguinGame.startScreenshotScene）で各場面を直接開く。
set -euo pipefail

cd "$(dirname "$0")/.."
out=build/screenshots
mkdir -p "$out"
bundle=com.hority.helloflight

pick() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in ds if re.search(sys.argv[1], d["name"])]
print(devices[-1]["udid"])' "$1"
}
iphone=$(pick 'iPhone.*Pro Max')
ipad=$(pick 'iPad Pro.*13')

xcodebuild -project HelloFlight.xcodeproj -scheme HelloFlight -configuration Debug -destination "id=$iphone" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build > build/xcodebuild.log 2>&1 || { tail -50 build/xcodebuild.log; exit 1; }
app=build/DerivedData/Build/Products/Debug-iphonesimulator/HelloFlight.app

shot() {
  local device=$1 name=$2
  shift 2
  xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
  xcrun simctl launch "$device" "$bundle" -penguin.tutorialDone YES "$@" > /dev/null
  sleep 12
  xcrun simctl io "$device" screenshot "$out/$name.png"
}

for pair in "iphone:$iphone" "ipad:$ipad"; do
  tag=${pair%%:*}
  device=${pair#*:}
  xcrun simctl boot "$device"
  xcrun simctl bootstatus "$device" -b > /dev/null
  xcrun simctl status_bar "$device" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
  xcrun simctl install "$device" "$app"
  # 1回目はシェーダーの準備で遅いので、撮らずに起動しておく（落ちたときの原因調べにコンソール出力を残す）。
  xcrun simctl launch --console-pty "$device" "$bundle" > "$out/$tag-console.txt" 2>&1 &
  console=$!
  sleep 15
  kill "$console" 2>/dev/null || true
  shot "$device" "$tag-1-title" -shot title -penguin.character unicorn -penguin.food 0
  shot "$device" "$tag-2-hiragana" -shot quiz -shotMode hiragana -penguin.character penguin -penguin.food 3
  shot "$device" "$tag-3-math" -shot quiz -shotMode math -penguin.character octopus -penguin.food 6
  shot "$device" "$tag-4-feed" -shot feed -penguin.character ghost -penguin.food 5
  shot "$device" "$tag-5-english" -shot quiz -shotMode alphabet -penguin.character unicorn -penguin.food 8
  xcrun simctl shutdown "$device"
done
# クラッシュしていたら、その記録も一緒に置く。
for report in ~/Library/Logs/DiagnosticReports/HelloFlight*; do
  [ -e "$report" ] && cp "$report" "$out/$(basename "$report").txt"
done
ls -la "$out"
