#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
CONFIGURATION=${1:-debug}
VERSION=${SLOPSHOT_VERSION:-0.1.0}
BUILD_NUMBER=${SLOPSHOT_BUILD_NUMBER:-1}
OUTPUT_DIR="$PROJECT_DIR/.build/app/$CONFIGURATION"
APP_DIR="$OUTPUT_DIR/SlopShot.app"

case "$CONFIGURATION" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

cd "$PROJECT_DIR"
swift build -c "$CONFIGURATION" --arch arm64
BIN_DIR=$(swift build -c "$CONFIGURATION" --arch arm64 --show-bin-path)

/bin/rm -rf -- "$APP_DIR"
/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/bin/cp "$BIN_DIR/SlopShot" "$APP_DIR/Contents/MacOS/SlopShot"
/bin/cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
/usr/bin/codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "com.prashantbhudwal.slopshot"' \
  "$APP_DIR"

echo "$APP_DIR"
