#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
(cd "$PROJECT_DIR" && swift build -c release)
BIN_DIR="$(cd "$PROJECT_DIR" && swift build -c release --show-bin-path)"
APP_PATH="$PROJECT_DIR/dist/FanCurve.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/FanCurve-build.XXXXXX")"
STAGED_APP_PATH="$STAGING_DIR/FanCurve.app"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p \
    "$STAGED_APP_PATH/Contents/MacOS" \
    "$STAGED_APP_PATH/Contents/Resources" \
    "$STAGED_APP_PATH/Contents/Library/PrivilegedHelperTools" \
    "$STAGED_APP_PATH/Contents/Library/LaunchDaemons"

COPYFILE_DISABLE=1 cp "$BIN_DIR/FanCurve" "$STAGED_APP_PATH/Contents/MacOS/FanCurve"
COPYFILE_DISABLE=1 cp "$BIN_DIR/FanCurveHelper" \
    "$STAGED_APP_PATH/Contents/Library/PrivilegedHelperTools/com.paink.FanCurve.helper"
COPYFILE_DISABLE=1 cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP_PATH/Contents/Info.plist"
COPYFILE_DISABLE=1 cp "$PROJECT_DIR/Resources/AppIcon.icns" \
    "$STAGED_APP_PATH/Contents/Resources/AppIcon.icns"
COPYFILE_DISABLE=1 cp "$PROJECT_DIR/Resources/com.paink.FanCurve.helper.plist" \
    "$STAGED_APP_PATH/Contents/Library/LaunchDaemons/com.paink.FanCurve.helper.plist"

chmod 755 "$STAGED_APP_PATH/Contents/MacOS/FanCurve"
chmod 755 "$STAGED_APP_PATH/Contents/Library/PrivilegedHelperTools/com.paink.FanCurve.helper"

codesign --force --sign - \
    "$STAGED_APP_PATH/Contents/Library/PrivilegedHelperTools/com.paink.FanCurve.helper"
codesign --force --sign - "$STAGED_APP_PATH/Contents/MacOS/FanCurve"
codesign --force --deep --sign - "$STAGED_APP_PATH"
codesign --verify --deep --strict "$STAGED_APP_PATH"

mkdir -p "$PROJECT_DIR/dist"
rm -rf "$APP_PATH"
ditto --norsrc --noextattr "$STAGED_APP_PATH" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "Application built: $APP_PATH"
