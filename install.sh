#!/bin/sh
set -eu

REPOSITORY=${SLOPSHOT_RELEASE_REPOSITORY:-prashantbhudwal/slopshot}
INSTALL_ROOT=${SLOPSHOT_INSTALL_ROOT:-"$HOME/Applications"}
RELEASE_ROOT="https://github.com/$REPOSITORY/releases/latest/download"
WORK_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/SlopShot-install.XXXXXX")
ARCHIVE="$WORK_DIR/SlopShot-arm64.zip"
CHECKSUM="$WORK_DIR/SlopShot-arm64.zip.sha256"
EXTRACTED="$WORK_DIR/extracted"
APP="$INSTALL_ROOT/SlopShot.app"
EXPECTED_IDENTIFIER="com.prashantbhudwal.slopshot"

say() { /bin/echo "SlopShot: $*"; }
fail() { /bin/echo "SlopShot: $*" >&2; exit 1; }

cleanup() { /bin/rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT INT TERM

MACHINE_ARCH=$(/usr/bin/uname -m)
if [ "$MACHINE_ARCH" = "x86_64" ] && [ "$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null || true)" = "1" ]; then
  MACHINE_ARCH="arm64"
fi
[ "$MACHINE_ARCH" = "arm64" ] || fail "Apple silicon is required."

MACOS_VERSION=$(/usr/bin/sw_vers -productVersion)
MACOS_MAJOR=${MACOS_VERSION%%.*}
[ "$MACOS_MAJOR" -ge 14 ] || fail "macOS 14 or later is required."

say "Downloading the latest release"
CURL_OPTIONS="--fail --location --silent --show-error --retry 3 --retry-all-errors"
# shellcheck disable=SC2086
/usr/bin/curl $CURL_OPTIONS "$RELEASE_ROOT/SlopShot-arm64.zip" -o "$ARCHIVE"
# shellcheck disable=SC2086
/usr/bin/curl $CURL_OPTIONS "$RELEASE_ROOT/SlopShot-arm64.zip.sha256" -o "$CHECKSUM"

say "Verifying the download"
(
  cd "$WORK_DIR"
  /usr/bin/shasum -a 256 -c "$(basename "$CHECKSUM")"
)

/bin/mkdir -p "$EXTRACTED"
/usr/bin/ditto -x -k "$ARCHIVE" "$EXTRACTED"
NEW_APP="$EXTRACTED/SlopShot.app"
[ -d "$NEW_APP" ] || fail "The release does not contain SlopShot.app."
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$NEW_APP/Contents/Info.plist")" = "$EXPECTED_IDENTIFIER" ] || fail "The downloaded app has the wrong bundle identifier."
/usr/bin/lipo "$NEW_APP/Contents/MacOS/SlopShot" -verify_arch arm64 >/dev/null || fail "The downloaded app is not arm64."

if ! /usr/bin/codesign --verify --deep --strict "$NEW_APP" 2>/dev/null; then
  say "Applying an ad-hoc signature"
  /usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --requirements '=designated => identifier "com.prashantbhudwal.slopshot"' \
    "$NEW_APP"
fi
/usr/bin/codesign --verify --deep --strict "$NEW_APP" || fail "The app signature could not be verified."

/bin/mkdir -p "$INSTALL_ROOT"
if /usr/bin/pgrep -x SlopShot >/dev/null 2>&1; then
  say "Stopping the running app"
  /usr/bin/pkill -TERM -x SlopShot
  WAIT_COUNT=0
  while /usr/bin/pgrep -x SlopShot >/dev/null 2>&1 && [ "$WAIT_COUNT" -lt 30 ]; do
    /bin/sleep 0.1
    WAIT_COUNT=$((WAIT_COUNT + 1))
  done
  /usr/bin/pgrep -x SlopShot >/dev/null 2>&1 && fail "The running app did not quit."
fi

BACKUP=""
if [ -e "$APP" ]; then
  BACKUP="$INSTALL_ROOT/SlopShot.previous.$(/bin/date +%Y%m%d%H%M%S).$$.app"
  say "Keeping the current app at $BACKUP"
  /bin/mv "$APP" "$BACKUP"
fi
if ! /bin/mv "$NEW_APP" "$APP"; then
  if [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then
    /bin/mv "$BACKUP" "$APP"
  fi
  fail "The app could not be installed."
fi
/usr/bin/xattr -dr com.apple.quarantine "$APP"
/usr/bin/open "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
say "Installed version $VERSION at $APP"
