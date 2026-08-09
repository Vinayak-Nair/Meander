#!/usr/bin/env bash
# Regenerates every Meander brand asset (app icon, menu-bar template, in-app mark,
# Branding/ exports) from the designer's artwork PNG. Re-run whenever the mark
# changes. The source of truth is Branding/meander-mark-source.png (a transparent
# PNG); each asset trims and composites it so it reproduces the artwork exactly.
set -euo pipefail
cd "$(dirname "$0")/.."

R="scripts/render_assets.swift"
SRC="Branding/meander-mark-source.png"
ICONSET="Sources/MeanderApp/Assets.xcassets/AppIcon.appiconset"
MENU="Sources/MeanderApp/Assets.xcassets/MenuBarIcon.imageset"
MARK="Sources/MeanderApp/Assets.xcassets/BrandMark.imageset"
mkdir -p "$ICONSET" "$MENU" "$MARK" Branding
export MEANDER_SRC="$SRC"

echo "==> App icon"
for s in 16 32 64 128 256 512 1024; do
  swift "$R" imgicon "$s" "$ICONSET/icon_$s.png"
done

echo "==> Menu-bar template"
swift "$R" menubar 16 "$MENU/menubar_16.png"
swift "$R" menubar 32 "$MENU/menubar_32.png"

echo "==> In-app mark"
swift "$R" imgcrop 600  "$MARK/mark.png"
swift "$R" imgcrop 1200 "$MARK/mark@2x.png"

echo "==> Branding exports"
swift "$R" imgcrop  1600     Branding/meander-mark.png
swift "$R" imgpanel  1600 900 Branding/meander-mark-dark.png
swift "$R" imglockup 1600 600 Branding/meander-lockup-dark.png
swift "$R" imgicon   1024     Branding/meander-app-icon.png

echo "==> Done"
