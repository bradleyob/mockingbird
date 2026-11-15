#!/bin/sh
# Builds the MockingBirdApp product in release mode and assembles an ad-hoc-signed
# build/MockingBird.app around it. No Xcode required; Command Line Tools are enough.
#
#   ./scripts/bundle-app.sh            # -> build/MockingBird.app
#   BUILD_DIR=/tmp/out ./scripts/bundle-app.sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-"$ROOT/build"}
PLIST="$ROOT/Support/MockingBirdApp/Info.plist"
APP="$BUILD_DIR/MockingBird.app"
PRODUCT=MockingBirdApp
EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$PLIST")

if [ "$(uname)" != "Darwin" ]; then
    echo "bundle-app.sh: macOS only" >&2
    exit 1
fi

cd "$ROOT"
swift build -c release --product "$PRODUCT"
BIN_DIR=$(swift build -c release --product "$PRODUCT" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$PLIST" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM resource bundles, if any target ever declares resources.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

plutil -lint "$APP/Contents/Info.plist" >/dev/null
# Ad-hoc signature: runs locally, not distributable. Microphone access needs no
# entitlement without the hardened runtime.
codesign --force --sign - --identifier "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
