#!/bin/sh
# Sizes build/icon/*.png (from render_icon_test.dart) into every Android and
# iOS icon slot. macOS only (uses sips).
set -eu
cd "$(dirname "$0")/../.."
SRC=build/icon
test -f "$SRC/icon.png" || { echo "Run: flutter test tool/icon/render_icon_test.dart"; exit 1; }
TMP=$(mktemp -d)

# Flatten to opaque: the App Store rejects icons with an alpha channel.
sips -s format jpeg -s formatOptions 100 "$SRC/icon.png" --out "$TMP/icon.jpg" >/dev/null
sips -s format png "$TMP/icon.jpg" --out "$TMP/opaque.png" >/dev/null

# iOS: one file per slot named in Contents.json, e.g. Icon-App-20x20@3x.png.
IOS=ios/Runner/Assets.xcassets/AppIcon.appiconset
for f in "$IOS"/Icon-App-*.png; do
  name=$(basename "$f" .png)
  pt=$(echo "$name" | sed -E 's/Icon-App-([0-9.]+)x.*/\1/')
  scale=$(echo "$name" | sed -E 's/.*@([0-9])x/\1/')
  px=$(echo "$pt * $scale" | bc | cut -d. -f1)
  sips -z "$px" "$px" "$TMP/opaque.png" --out "$f" >/dev/null
done

# Android: legacy icons, plus adaptive layers (108 dp) for Android 8+.
RES=android/app/src/main/res
for pair in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  d=$(echo "$pair" | cut -d: -f1); legacy=$(echo "$pair" | cut -d: -f2); layer=$(echo "$pair" | cut -d: -f3)
  sips -z "$legacy" "$legacy" "$TMP/opaque.png" --out "$RES/mipmap-$d/ic_launcher.png" >/dev/null
  sips -z "$layer" "$layer" "$SRC/foreground.png" --out "$RES/mipmap-$d/ic_launcher_foreground.png" >/dev/null
  sips -z "$layer" "$layer" "$SRC/background.png" --out "$RES/mipmap-$d/ic_launcher_background.png" >/dev/null
done
mkdir -p "$RES/mipmap-anydpi-v26"
cat > "$RES/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
XML
rm -rf "$TMP"
echo "Icons installed."
