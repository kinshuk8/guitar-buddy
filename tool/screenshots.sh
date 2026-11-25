#!/usr/bin/env bash
# Takes the README's screenshots from the running app on an iOS simulator.
#   tool/screenshots.sh [DEVICE] [OUT_DIR]
# Dark mode, a clean status bar (9:41, full signal and battery), then
# integration_test/screenshots_test.dart walks the app and prints
# "SHOT <name>" at each screen; each is saved as OUT_DIR/<name>.png.
set -euo pipefail
device="${1:-booted}"
out="${2:-build/screenshots}"
mkdir -p "$out"
xcrun simctl ui "$device" appearance dark
xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
udid="$device"
if [ "$device" = booted ]; then
  udid=$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -1)
fi
flutter test integration_test/screenshots_test.dart -d "$udid" 2>&1 | while IFS= read -r line; do
  echo "$line"
  case "$line" in
    *"SHOT "*)
      name="${line##*SHOT }"
      xcrun simctl io "$device" screenshot "$out/$name.png" >/dev/null 2>&1
      echo "  saved $out/$name.png"
      ;;
  esac
done
xcrun simctl status_bar "$device" clear
