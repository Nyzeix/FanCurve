#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH=""

if [[ -x "$SCRIPT_DIR/build-app.sh" ]]; then
    "$SCRIPT_DIR/build-app.sh"
    APP_PATH="$PROJECT_DIR/dist/FanCurve.app"
elif [[ -d "$SCRIPT_DIR/FanCurve.app" ]]; then
    APP_PATH="$SCRIPT_DIR/FanCurve.app"
elif [[ -d "/Applications/FanCurve.app" ]]; then
    APP_PATH="/Applications/FanCurve.app"
else
    echo "FanCurve.app was not found next to this script or in /Applications." >&2
    exit 1
fi

HELPER_PATH="$APP_PATH/Contents/Library/PrivilegedHelperTools/com.paink.FanCurve.helper"
PLIST_PATH="$APP_PATH/Contents/Library/LaunchDaemons/com.paink.FanCurve.helper.plist"
INSTALLED_HELPER="/Library/PrivilegedHelperTools/com.paink.FanCurve.helper"
INSTALLED_PLIST="/Library/LaunchDaemons/com.paink.FanCurve.helper.plist"

if [[ ! -x "$HELPER_PATH" || ! -f "$PLIST_PATH" ]]; then
    echo "The FanCurve helper files are missing from $APP_PATH." >&2
    exit 1
fi

sudo install -d -m 755 /Library/PrivilegedHelperTools /Library/LaunchDaemons
sudo install -m 755 "$HELPER_PATH" "$INSTALLED_HELPER"
sudo install -m 644 "$PLIST_PATH" "$INSTALLED_PLIST"

if sudo launchctl print system/com.paink.FanCurve.helper >/dev/null 2>&1; then
    sudo launchctl kickstart -k system/com.paink.FanCurve.helper
else
    sudo launchctl bootstrap system "$INSTALLED_PLIST"
fi

echo "FanCurve helper installed. Quit and reopen FanCurve to verify its availability."
