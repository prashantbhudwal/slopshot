#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(/bin/sh "$SCRIPT_DIR/build-app.sh" debug | /usr/bin/tail -n 1)
/usr/bin/open -n "$APP_DIR"
echo "$APP_DIR"
