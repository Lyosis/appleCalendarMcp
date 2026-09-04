#!/bin/bash
#
# Builds AppleCalendarMCP.app: the helper agent, the bridge, and the launch
# agent property list, in one signed bundle.
#
#   Scripts/build-app.sh [--release] [--sign <identity>] [--install <dir>]
#
# Staging happens outside the source tree on purpose. A checkout inside iCloud
# Drive (~/Documents and ~/Desktop are synced by default) collects
# com.apple.FinderInfo and com.apple.fileprovider attributes that codesign
# refuses outright, and that the file provider puts straight back after
# `xattr -c`. Assembling in /tmp sidesteps that entirely.

set -euo pipefail

CONFIGURATION="debug"
IDENTITY="-"
INSTALL_DIR="$HOME/Applications"

while [ $# -gt 0 ]; do
	case "$1" in
		--release) CONFIGURATION="release"; shift ;;
		--sign) IDENTITY="$2"; shift 2 ;;
		--install) INSTALL_DIR="$2"; shift 2 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(mktemp -d /tmp/apple-calendar-mcp-build.XXXXXX)"
APP="$STAGE/AppleCalendarMCP.app"
DESTINATION="$INSTALL_DIR/AppleCalendarMCP.app"

trap 'rm -rf "$STAGE"' EXIT

echo "==> building ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --package-path "$ROOT" >/dev/null
BIN="$ROOT/.build/$CONFIGURATION"

echo "==> assembling"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchAgents"
cp "$BIN/apple-calendar-mcp" "$APP/Contents/MacOS/"
cp "$BIN/apple-calendar-mcp-bridge" "$APP/Contents/MacOS/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/LaunchAgents/"*.plist "$APP/Contents/Library/LaunchAgents/"
xattr -cr "$APP"

echo "==> signing ($IDENTITY)"
# Inside out. Signing the bundle seals a second executable in Contents/MacOS as
# a nested resource without re-signing it, so the bridge would keep SwiftPM's
# ad-hoc signature — and the helper, which requires its peers to share its team
# identifier, would refuse it.
codesign --force --options runtime --sign "$IDENTITY" "$APP/Contents/MacOS/apple-calendar-mcp-bridge"
codesign --force --options runtime --sign "$IDENTITY" "$APP/Contents/MacOS/apple-calendar-mcp"
codesign --force --options runtime --sign "$IDENTITY" "$APP"

# Assert on the artefact, never on the intention.
codesign --verify --strict "$APP"

# --verify passes with an ad-hoc nested executable, so it cannot catch the
# mistake above. Check every executable's team identifier directly.
BUNDLE_TEAM="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
for EXECUTABLE in "$APP/Contents/MacOS/"*; do
	EXECUTABLE_TEAM="$(codesign -dvv "$EXECUTABLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
	if [ "$EXECUTABLE_TEAM" != "$BUNDLE_TEAM" ]; then
		echo "$(basename "$EXECUTABLE"): team is '${EXECUTABLE_TEAM:-none}', the bundle's is '${BUNDLE_TEAM:-none}'" >&2
		echo "the helper would refuse this binary at run time" >&2
		exit 1
	fi
done
PLIST="$APP/Contents/Library/LaunchAgents/com.wilfrid.B.apple-calendar-mcp.agent.plist"
test -f "$PLIST" || { echo "the launch agent plist is missing from the bundle" >&2; exit 1; }
VERSION_IN_PLIST="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
VERSION_IN_CODE="$("$APP/Contents/MacOS/apple-calendar-mcp" --version)"
if [ "$VERSION_IN_PLIST" != "$VERSION_IN_CODE" ]; then
	echo "version drift: plist says $VERSION_IN_PLIST, the binary says $VERSION_IN_CODE" >&2
	exit 1
fi

# An installed copy must be unregistered before it is replaced: launchd binds
# the agent to the bundle path present at registration, and silently refuses
# the job afterwards if that path has changed underneath it.
if [ -x "$DESTINATION/Contents/MacOS/apple-calendar-mcp" ]; then
	echo "==> unregistering the installed copy"
	"$DESTINATION/Contents/MacOS/apple-calendar-mcp" --unregister-agent >/dev/null 2>&1 || true
fi

echo "==> installing to $DESTINATION"
mkdir -p "$INSTALL_DIR"
rm -rf "$DESTINATION"
ditto "$APP" "$DESTINATION"

echo
echo "built    $DESTINATION"
echo "version  $VERSION_IN_CODE"
echo "signed   $(codesign -dvv "$DESTINATION" 2>&1 | grep -E '^Authority=' | head -1 | cut -d= -f2- || true)"
echo "         $(codesign -dvv "$DESTINATION" 2>&1 | grep -E '^Signature=' | head -1 || echo 'Signature=?')"
echo
echo "next:"
echo "  '$DESTINATION/Contents/MacOS/apple-calendar-mcp' --register-agent"
echo "  '$DESTINATION/Contents/MacOS/apple-calendar-mcp' --pin-client-auto"
echo "  bridge: $DESTINATION/Contents/MacOS/apple-calendar-mcp-bridge"
