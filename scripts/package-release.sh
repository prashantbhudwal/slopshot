#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
VERSION=${1:-0.1.0}
DIST_DIR="$PROJECT_DIR/dist"

SLOPSHOT_VERSION="$VERSION" /bin/sh "$SCRIPT_DIR/build-app.sh" release
/bin/mkdir -p "$DIST_DIR"
/bin/rm -f -- "$DIST_DIR/SlopShot-arm64.zip" "$DIST_DIR/SlopShot-arm64.zip.sha256"
DITTONORSRC=1 /usr/bin/ditto \
  -c \
  -k \
  --keepParent \
  --norsrc \
  --noextattr \
  --noqtn \
  --noacl \
  "$PROJECT_DIR/.build/app/release/SlopShot.app" \
  "$DIST_DIR/SlopShot-arm64.zip"
(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 SlopShot-arm64.zip > SlopShot-arm64.zip.sha256
)

echo "$DIST_DIR"
