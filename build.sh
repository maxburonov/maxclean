#!/bin/zsh
# Max Clean — Apple Silicon uchun .app va .dmg yig'ish
# Ishlatish:  ./build.sh            (versiya: 0.1.2)
#             ./build.sh 0.1.3      (yangi versiya)
set -e
cd "$(dirname "$0")"

VERSION="${1:-0.1.7}"
BUILD="$(date +%Y%m%d%H%M)"
APP="build/Max Clean.app"

echo "▶ Kompilyatsiya (arm64, release)…"
swift build -c release --arch arm64

BIN="$(swift build -c release --arch arm64 --show-bin-path)/MaxClean"

echo "▶ .app paketi…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MaxClean"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "▶ Ikonka…"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# "Max Clean Dev" sertifikati bo'lsa — barqaror imzo (Full Disk Access har build'da yo'qolmaydi)
IDENTITY="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "Max Clean Dev"; then IDENTITY="Max Clean Dev"; fi
echo "▶ Imzolash ($IDENTITY)…"
codesign --force --deep --sign "$IDENTITY" "$APP" || codesign --force --deep --sign - "$APP"

echo "▶ DMG…"
DMG="build/MaxClean-$VERSION.dmg"
rm -f "$DMG"
STAGE="build/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Max Clean" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE" "$ICONSET"

echo "✅ Tayyor: $APP"
echo "✅ DMG:    $DMG"
echo "Ishga tushirish: open \"$APP\""
