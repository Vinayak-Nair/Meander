#!/usr/bin/env bash
# Dev build + run: regenerates the Xcode project, builds the app, signs it with
# the stable "Meander Dev" identity, deploys a SINGLE canonical copy to
# /Applications, and launches it.
#
# Why a single canonical copy: macOS ties Accessibility / Input Monitoring grants
# to (bundle id + code signature). Multiple Meander.app copies with different
# signatures — or "Quit & Reopen" launching a different copy than you granted —
# makes permissions look like they reset. One app, one location, one signature
# keeps the grants stable across rebuilds.
#
# Run scripts/setup-dev-cert.sh once first so the "Meander Dev" identity exists.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Debug
DD=build/dd
BUILT="$DD/Build/Products/$CONFIG/Meander.app"
DEST="/Applications/Meander.app"
CERT_NAME="Meander Dev"

echo "==> Generating project"
xcodegen generate >/dev/null

# Resolve the exact identity hash (signing by hash, not name, avoids xcodebuild
# matching a similarly-named cert).
IDENTITY=$(security find-identity -p codesigning 2>/dev/null \
  | grep "\"$CERT_NAME\"" | awk '{print $2}' | head -1 || true)

SIGN_ARGS=()
if [ -n "$IDENTITY" ]; then
  echo "==> Building ($CONFIG) signed with '$CERT_NAME' ($IDENTITY)"
  # ENABLE_DEBUG_DYLIB=NO: the Debug "debug dylib" split enforces strict team-id
  # matching between the launcher stub and the dylib, which a non-Apple identity
  # (no team id) fails — dyld then refuses to load it.
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" OTHER_CODE_SIGN_FLAGS="--timestamp=none" ENABLE_DEBUG_DYLIB=NO)
else
  echo "==> Building ($CONFIG) — '$CERT_NAME' identity not found, using ad-hoc."
  echo "    Run scripts/setup-dev-cert.sh so the hotkey permissions persist."
fi

# -skipPackagePluginValidation / -skipMacroValidation: MLX pulls build-tool
# plugins (CudaBuild) and swift-syntax macros that Xcode otherwise gates behind
# an interactive trust prompt, which fails a non-interactive build.
xcodebuild -project Meander.xcodeproj -scheme Meander -configuration "$CONFIG" \
  -derivedDataPath "$DD" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
  -skipPackagePluginValidation -skipMacroValidation build >/dev/null

echo "==> Deploying to $DEST"
pkill -x Meander 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"

echo "==> Launching"
open "$DEST"
echo "Done: $DEST"
