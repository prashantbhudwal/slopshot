#!/bin/sh
set -eu

REPOSITORY=${SLOPSHOT_RELEASE_REPOSITORY:-prashantbhudwal/slopshot}
INSTALL_ROOT=${SLOPSHOT_INSTALL_ROOT:-"$HOME/Applications"}
RELEASE_ROOT="https://github.com/$REPOSITORY/releases/latest/download"
WORK_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/SlopShot-install.XXXXXX")
ARCHIVE="$WORK_DIR/SlopShot-arm64.zip"
CHECKSUM="$WORK_DIR/SlopShot-arm64.zip.sha256"
SIGNATURE="$WORK_DIR/SlopShot-arm64.zip.sha256.sig"
ALLOWED_SIGNERS="$WORK_DIR/allowed_signers"
EXTRACTED="$WORK_DIR/extracted"
APP="$INSTALL_ROOT/SlopShot.app"
EXPECTED_IDENTIFIER="com.prashantbhudwal.slopshot"
RELEASE_SIGNING_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGVUrQY5WnBoNfwX4c6Tzcrd6mCnkqSi6fK7HVTuigJW"

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
# shellcheck disable=SC2086
/usr/bin/curl $CURL_OPTIONS "$RELEASE_ROOT/SlopShot-arm64.zip.sha256.sig" -o "$SIGNATURE"

say "Verifying the signed release"
/usr/bin/printf '%s\n' "slopshot-release $RELEASE_SIGNING_PUBLIC_KEY" > "$ALLOWED_SIGNERS"
if ! /usr/bin/ssh-keygen \
  -Y verify \
  -f "$ALLOWED_SIGNERS" \
  -I slopshot-release \
  -n slopshot-release \
  -s "$SIGNATURE" \
  < "$CHECKSUM" \
  >/dev/null 2>&1
then
  fail "The release signature is invalid."
fi
EXPECTED_HASH=$(
  /usr/bin/awk '
    NF {
      count += 1
      if (NF == 2 && $1 ~ /^[0-9a-fA-F]{64}$/ && $2 == "SlopShot-arm64.zip") {
        hash = tolower($1)
      }
    }
    END { if (count == 1 && hash != "") print hash }
  ' "$CHECKSUM"
)
[ -n "$EXPECTED_HASH" ] || fail "The signed checksum manifest is invalid."
ACTUAL_HASH=$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print tolower($1)}')
[ "$ACTUAL_HASH" = "$EXPECTED_HASH" ] || fail "The downloaded archive failed verification."

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
if ! /usr/bin/xattr -dr com.apple.quarantine "$APP" || ! /usr/bin/open "$APP"; then
  /bin/rm -rf -- "$APP"
  if [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then
    /bin/mv "$BACKUP" "$APP"
    /usr/bin/open "$APP" || true
  fi
  fail "The new app could not be launched; the previous version was restored."
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
say "Installed version $VERSION at $APP"
