#!/bin/bash
#
# Builds AppleCalendarMCP.app: the helper agent, the bridge, and the launch
# agent property list, in one signed bundle.
#
#   Scripts/build-app.sh [--release] [--sign <identity>] [--install <dir>]
#                        [--force] [--allow-adhoc-downgrade]
#
# Staging happens outside the source tree on purpose. A checkout inside iCloud
# Drive (~/Documents and ~/Desktop are synced by default) collects
# com.apple.FinderInfo and com.apple.fileprovider attributes that codesign
# refuses outright, and that the file provider puts straight back after
# `xattr -c`. Assembling in /tmp sidesteps that entirely.
#
# Re-signing is destructive, which is why this script would rather do nothing.
# TCC records a grant against the helper's code signature, so signing again
# makes it a different client and silently drops the calendar permission — the
# person has to answer the prompt afterwards with no idea why. Worse under an
# ad-hoc signature, which TCC pins by content hash: every changed byte is a new
# client. So an install whose sources and signing identity are unchanged is left
# strictly alone, and a certificate-signed install is never quietly replaced by
# an ad-hoc one.
#
# (Both of those are owed to omarshahine/apple-pim, which hit them first.)

set -euo pipefail

CONFIGURATION="debug"
IDENTITY="-"
INSTALL_DIR="$HOME/Applications"
FORCE=false
ALLOW_DOWNGRADE=false

while [ $# -gt 0 ]; do
	case "$1" in
		--release) CONFIGURATION="release"; shift ;;
		--sign) IDENTITY="$2"; shift 2 ;;
		--install) INSTALL_DIR="$2"; shift 2 ;;
		--force) FORCE=true; shift ;;
		--allow-adhoc-downgrade) ALLOW_DOWNGRADE=true; shift ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/Resources/AppleCalendarMCP.entitlements"
STAGE="$(mktemp -d /tmp/apple-calendar-mcp-build.XXXXXX)"
APP="$STAGE/AppleCalendarMCP.app"
DESTINATION="$INSTALL_DIR/AppleCalendarMCP.app"

trap 'rm -rf "$STAGE"' EXIT

echo "==> building ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --package-path "$ROOT" >/dev/null
# Ask where the products actually are rather than assuming .build/<config>:
# Swift 6 puts them under .build/out/Products/<Config>.
BIN="$(swift build -c "$CONFIGURATION" --package-path "$ROOT" --show-bin-path)"

echo "==> assembling"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchAgents" "$APP/Contents/Resources"

# The window's localisations. SwiftPM compiles the string catalog into a
# resource bundle beside the binaries; Bundle.module finds it in the app's
# Resources folder, and without it every label silently falls back to its
# English key.
RESOURCE_BUNDLE="$BIN/apple-calendar-mcp_AppleCalendarMCPApp.bundle"
test -d "$RESOURCE_BUNDLE" || {
	echo "the window's resource bundle is missing from $BIN" >&2
	exit 1
}
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

# A real .lproj in the app bundle itself, not only in the nested one. It carries
# the permission prompt's translated text, and its presence is also what tells
# macOS the app speaks French at all — without it the process runs in English
# and never consults the window's catalog.
cp -R "$ROOT/Resources/"*.lproj "$APP/Contents/Resources/"
cp "$BIN/AppleCalendarMCP" "$APP/Contents/MacOS/"
cp "$BIN/apple-calendar-mcp" "$APP/Contents/MacOS/"
cp "$BIN/apple-calendar-mcp-bridge" "$APP/Contents/MacOS/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/LaunchAgents/"*.plist "$APP/Contents/Library/LaunchAgents/"
xattr -cr "$APP"

# A fingerprint of what went in, before signing touches any of it. The installed
# bundle's own bytes cannot be compared against these: signing rewrites the
# binaries in place, so the copy on disk never matches the copy just built.
STAMP_REL="Contents/Resources/.build-sources"
mkdir -p "$APP/Contents/Resources"
SOURCES_HASH="$(
	find "$APP" -type f ! -name ".build-sources" -exec shasum -a 256 {} + \
		| sed "s|$APP/||" | sort -k2 | shasum -a 256 | awk '{print $1}'
)"
# The entitlements are applied at signing and never copied into the bundle, so
# hash them separately: otherwise a change to them alone would leave an
# installed copy "unchanged" and the fix would never ship.
ENTITLEMENTS_HASH="$(shasum -a 256 "$ENTITLEMENTS" | awk '{print $1}')"
printf 'sources=%s\nentitlements=%s\nidentity=%s\n' "$SOURCES_HASH" "$ENTITLEMENTS_HASH" "$IDENTITY" > "$APP/$STAMP_REL"

# Nothing to do when the install already holds these exact sources under this
# exact identity, and its signature is still intact.
if [ "$FORCE" = false ] && [ -d "$DESTINATION" ] && [ -f "$DESTINATION/$STAMP_REL" ]; then
	if cmp -s "$APP/$STAMP_REL" "$DESTINATION/$STAMP_REL" \
		&& codesign --verify --strict "$DESTINATION" 2>/dev/null; then
		echo
		echo "unchanged  $DESTINATION"
		echo "           same sources, same identity, signature intact — left alone,"
		echo "           because re-signing would drop the calendar permission."
		echo "           Pass --force to rebuild anyway."
		exit 0
	fi
fi

# Replacing a certificate-signed install with an ad-hoc one looks like a routine
# reinstall and costs the person every grant. Refuse by default.
if [ "$IDENTITY" = "-" ] && [ "$ALLOW_DOWNGRADE" = false ] && [ -d "$DESTINATION" ]; then
	INSTALLED_TEAM="$(codesign -dvv "$DESTINATION" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
	if [ -n "$INSTALLED_TEAM" ] && [ "$INSTALLED_TEAM" != "not set" ]; then
		echo "the install at $DESTINATION is signed by team $INSTALLED_TEAM." >&2
		echo "signing ad-hoc over it would drop its calendar permission." >&2
		echo "pass --sign <identity>, or --allow-adhoc-downgrade to accept that." >&2
		exit 1
	fi
fi

if [ "$IDENTITY" = "-" ]; then
	echo "note: ad-hoc signature — TCC pins it by content hash, so every rebuild"
	echo "      that changes a byte asks for the calendar permission again."
fi

# Notarisation requires a secure timestamp, and a signature without one is
# rejected at submission. codesign is documented to add a timestamp by default
# under a Developer ID identity, but a default is not a guarantee on a point
# that fails the whole submission, so ask for it explicitly. An ad-hoc
# signature cannot carry one at all.
TIMESTAMP="--timestamp"
[ "$IDENTITY" = "-" ] && TIMESTAMP="--timestamp=none"

echo "==> signing ($IDENTITY)"
# Inside out. Signing the bundle seals a second executable in Contents/MacOS as
# a nested resource without re-signing it, so the bridge would keep SwiftPM's
# ad-hoc signature — and the helper, which requires its peers to share its team
# identifier, would refuse it.
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$APP/Contents/MacOS/apple-calendar-mcp-bridge"
codesign --force --options runtime "$TIMESTAMP" --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP/Contents/MacOS/apple-calendar-mcp"
codesign --force --options runtime "$TIMESTAMP" --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP/Contents/MacOS/AppleCalendarMCP"
# Signing the bundle re-signs its main executable, the window. Without the
# entitlements here too, the line above is silently undone.
codesign --force --options runtime "$TIMESTAMP" --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"

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

# The helper also requires the bridge's exact signing identifier. codesign takes
# it from the bridge's embedded plist, the helper from a constant in the source:
# three places that must agree, and a mismatch refuses every connection.
BRIDGE_SIGNED_AS="$(codesign -dv "$APP/Contents/MacOS/apple-calendar-mcp-bridge" 2>&1 | sed -n 's/^Identifier=//p')"
BRIDGE_IN_PLIST="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$ROOT/Resources/BridgeInfo.plist")"
BRIDGE_IN_CODE="$(sed -n 's/^public let bridgeSigningIdentifier = "\(.*\)"$/\1/p' "$ROOT/Sources/AppleCalendarIPC/IPC.swift")"
if [ "$BRIDGE_SIGNED_AS" != "$BRIDGE_IN_PLIST" ] || [ "$BRIDGE_SIGNED_AS" != "$BRIDGE_IN_CODE" ]; then
	echo "bridge identifier: signed '${BRIDGE_SIGNED_AS:-none}', plist '${BRIDGE_IN_PLIST:-none}', code '${BRIDGE_IN_CODE:-none}'" >&2
	echo "the helper would refuse the bridge at run time" >&2
	exit 1
fi

# A Developer ID signature with no timestamp passes --verify and fails
# notarisation, which is the worst order to find out. Assert it here.
#
# Capture the output before searching it. `codesign -dvv | grep -q` looks
# right and fails most of the time under pipefail: grep exits on the first
# match, codesign is still writing to the closed pipe, takes SIGPIPE, and the
# pipeline reports failure for a signature that is perfectly fine.
if [ "$IDENTITY" != "-" ]; then
	for EXECUTABLE in "$APP/Contents/MacOS/"* "$APP"; do
		SIGNATURE="$(codesign -dvv "$EXECUTABLE" 2>&1)"
		if ! grep -q "^Timestamp=" <<<"$SIGNATURE"; then
			echo "$(basename "$EXECUTABLE"): signed without a secure timestamp" >&2
			echo "notarisation would reject this" >&2
			exit 1
		fi
	done
fi

# The calendar entitlement, on exactly the executables that use EventKit. Its
# absence fails without a sound: the request goes out, no prompt ever appears.
for EXECUTABLE in AppleCalendarMCP apple-calendar-mcp apple-calendar-mcp-bridge; do
	GRANTED="$(codesign -d --entitlements - --xml "$APP/Contents/MacOS/$EXECUTABLE" 2>/dev/null)"
	if grep -q "personal-information.calendars" <<<"$GRANTED"; then HAS=yes; else HAS=no; fi
	if [ "$EXECUTABLE" = "apple-calendar-mcp-bridge" ]; then WANT=no; else WANT=yes; fi
	if [ "$HAS" != "$WANT" ]; then
		echo "$EXECUTABLE: calendar entitlement present=$HAS, expected=$WANT" >&2
		exit 1
	fi
done

# A localisation that is declared but not shipped is worse than none: every
# label falls back to its English key and nothing says why. English is the base
# language, so it has no table of its own — only the translations do.
FRENCH="$APP/Contents/Resources/apple-calendar-mcp_AppleCalendarMCPApp.bundle/Contents/Resources/fr.lproj/Localizable.strings"
test -s "$FRENCH" || { echo "the window is missing its French localisation" >&2; exit 1; }

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
# An ad-hoc signature reports Signature=adhoc; a certificate reports a
# Timestamp= line instead. Show whichever is there.
INSTALLED="$(codesign -dvv "$DESTINATION" 2>&1)"
echo "signed   $(sed -n '/^Authority=/{s/^Authority=//p;q;}' <<<"$INSTALLED")"
echo "         $(sed -En '/^(Signature|Timestamp)=/{p;q;}' <<<"$INSTALLED")"
echo
echo "next:"
echo "  '$DESTINATION/Contents/MacOS/apple-calendar-mcp' --register-agent"
echo "  '$DESTINATION/Contents/MacOS/apple-calendar-mcp' --pin-client-auto"
echo "  bridge: $DESTINATION/Contents/MacOS/apple-calendar-mcp-bridge"
