#!/usr/bin/env bash
# Builds a distributable Drift.dmg. Signs and notarizes when credentials are set.
#
# One-time notarization setup:
#   xcrun notarytool store-credentials drift-notary \
#     --apple-id "you@example.com" --team-id TEAMID --password APP_SPECIFIC_PW
#
# Then run:
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="drift-notary" ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME=Drift
CONFIG=Release
BUILD=build
ARCHIVE="$BUILD/Drift.xcarchive"
APP="$BUILD/export/Drift.app"
DMG="$BUILD/Drift.dmg"

command -v xcodegen >/dev/null 2>&1 || { echo "Run scripts/bootstrap.sh first." >&2; exit 1; }
xcodegen generate

echo "==> Archiving"
# mlx-swift ships a CudaBuild package plugin. Xcode's GUI asks once whether to
# trust it; xcodebuild has no way to answer and fails, so validation is skipped
# here. The plugin is inert on Apple silicon.
xcodebuild -project Drift.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -skipPackagePluginValidation -skipMacroValidation \
  -archivePath "$ARCHIVE" archive

echo "==> Exporting app"
mkdir -p "$BUILD/export"
rm -rf "$APP"
cp -R "$ARCHIVE/Products/Applications/Drift.app" "$BUILD/export/"

# Bundle the default English model (Parakeet v3) so first-run dictation needs no
# download. Source defaults to the local model cache; run the app once to populate
# it, or point MODEL_CACHE at a directory containing the parakeet-tdt-0.6b-v3 folder.
#
# v3 must match ModelManager.parakeetVersion. Only v3 exposes the joint top-K
# outputs the decoder's script filter needs, so bundling v2 would be ignored at
# load time and would drop the language guarantee.
MODEL_CACHE="${MODEL_CACHE:-$HOME/Library/Application Support/Drift/models/FluidAudio}"
MODEL_DIR="$MODEL_CACHE/parakeet-tdt-0.6b-v3"
if [ -d "$MODEL_DIR" ]; then
  echo "==> Bundling model from $MODEL_DIR"
  DEST="$APP/Contents/Resources/BundledModels/FluidAudio"
  mkdir -p "$DEST"
  cp -R "$MODEL_DIR" "$DEST/"
else
  echo "   (No model at $MODEL_DIR: shipping without a bundled model;"
  echo "    users will download it on first run. Set MODEL_CACHE to bundle it.)"
fi

# Bundle the MLX cleanup model. Unlike Parakeet there is no in-app download for
# it, so if it isn't bundled the "On-device LLM" cleanup option silently falls
# back to deterministic. Populate with scripts/fetch-eval-model.sh, or point
# MLX_MODEL_CACHE at a directory containing the qwen2.5-0.5b-4bit folder.
MLX_MODEL_CACHE="${MLX_MODEL_CACHE:-$PWD/eval/models}"
MLX_MODEL_DIR="$MLX_MODEL_CACHE/qwen2.5-0.5b-4bit"
if [ -d "$MLX_MODEL_DIR" ]; then
  echo "==> Bundling MLX cleanup model from $MLX_MODEL_DIR"
  MLX_DEST="$APP/Contents/Resources/BundledModels/mlx"
  mkdir -p "$MLX_DEST"
  cp -R "$MLX_MODEL_DIR" "$MLX_DEST/"
else
  echo "   (No MLX model at $MLX_MODEL_DIR: shipping without on-device LLM"
  echo "    cleanup. Run scripts/fetch-eval-model.sh to populate it.)"
fi

if [ -n "${DEV_ID:-}" ]; then
  echo "==> Signing with Developer ID + hardened runtime"
  codesign --force --options runtime --deep --sign "$DEV_ID" "$APP"
else
  echo "   (DEV_ID not set: ad-hoc signing. Distributable but not notarizable.)"
  codesign --force --deep --sign - "$APP"
fi

echo "==> Building DMG"
rm -f "$DMG"
# hdiutil can transiently fail with "Resource busy" when Spotlight/mdworker is
# touching the source app (common on CI runners). Retry a few times.
for attempt in 1 2 3 4 5; do
  if hdiutil create -volname Drift -srcfolder "$APP" -ov -format UDZO "$DMG"; then
    break
  fi
  if [ "$attempt" = 5 ]; then
    echo "hdiutil create failed after $attempt attempts." >&2
    exit 1
  fi
  echo "   (hdiutil busy; retrying in 5s — attempt $attempt of 5)"
  rm -f "$DMG"
  sleep 5
done

if [ -n "${NOTARY_PROFILE:-}" ] && [ -n "${DEV_ID:-}" ]; then
  echo "==> Notarizing (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
else
  echo "   (Notarization skipped: set DEV_ID and NOTARY_PROFILE to enable.)"
fi

echo ""
echo "Done: $DMG"
