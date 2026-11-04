#!/bin/bash
# Build Brian.dmg, the drag-to-Applications disk image.
#
# Icon centers match Scripts/render-installer-art.py:
# Brian.app at (180, 170), Applications at (480, 170), window content 660x400.
# The window is 28pt taller than the artwork so the title bar does not crop it.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "The installer window is built on macOS. This machine has no Finder or hdiutil." >&2
	exit 1
fi

"$root/Scripts/package-macos-app.sh"

stage="$(mktemp -d)"
workdir="$(mktemp -d)"
plist="$(mktemp)"
script="$(mktemp)"
disk=""
cleanup() {
	if [[ -n "$disk" ]]; then
		hdiutil detach "$disk" >/dev/null 2>&1 || true
	fi
	rm -rf "$stage" "$workdir" "$plist" "$script"
}
trap cleanup EXIT

cp -R "$root/Brian.app" "$stage/Brian.app"
ln -s /Applications "$stage/Applications"
mkdir -p "$stage/.background"
cp "$root/Scripts/installer-background.png" "$stage/.background/background.png"
cp "$root/Scripts/installer-background@2x.png" "$stage/.background/background@2x.png"
cp "$root/Scripts/AppIcon.icns" "$stage/.VolumeIcon.icns"

if mount | grep -F "/Volumes/Install Brian" >/dev/null 2>&1; then
	hdiutil detach "/Volumes/Install Brian" >/dev/null 2>&1 || true
fi

hdiutil create \
	-volname "Install Brian" \
	-srcfolder "$stage" \
	-fs HFS+ \
	-format UDRW \
	-ov \
	"$workdir/Brian-rw.dmg" >/dev/null

hdiutil attach \
	-readwrite \
	-noverify \
	-noautoopen \
	-nobrowse \
	-plist \
	"$workdir/Brian-rw.dmg" >"$plist"

disk="$(/usr/libexec/PlistBuddy -c 'Print system-entities:0:dev-entry' "$plist")"
mount_point=""
index=0
while true; do
	entry="$(/usr/libexec/PlistBuddy -c "Print system-entities:${index}:dev-entry" "$plist" 2>/dev/null || true)"
	if [[ -z "$entry" ]]; then
		break
	fi
	point="$(/usr/libexec/PlistBuddy -c "Print system-entities:${index}:mount-point" "$plist" 2>/dev/null || true)"
	if [[ -n "$point" ]]; then
		mount_point="$point"
	fi
	index=$((index + 1))
done

if [[ -z "$mount_point" ]]; then
	echo "The disk image mounted without a volume path." >&2
	exit 1
fi

if command -v SetFile >/dev/null 2>&1; then
	SetFile -a C "$mount_point" || true
fi

cat >"$script" <<'APPLESCRIPT'
on run argv
	set diskName to item 1 of argv
	tell application "Finder"
		tell disk diskName
			open
			set theXOrigin to 200
			set theYOrigin to 120
			set theWidth to 660
			set theHeight to 428
			set theBottomRightX to (theXOrigin + theWidth)
			set theBottomRightY to (theYOrigin + theHeight)
			tell container window
				set current view to icon view
				set toolbar visible to false
				set statusbar visible to false
				set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
				set position of every item to {900, 500}
			end tell
			set opts to the icon view options of container window
			tell opts
				set icon size to 128
				set text size to 13
				set arrangement to not arranged
			end tell
			set background picture of opts to file ".background:background.png"
			set position of item "Brian.app" to {180, 170}
			set the extension hidden of item "Brian.app" to true
			set position of item "Applications" to {480, 170}
			close
			open
			update without registering applications
			delay 2
			tell container window
				set statusbar visible to false
				set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
			end tell
			delay 2
		end tell
	end tell
end run
APPLESCRIPT

osascript "$script" "$(basename "$mount_point")"

chmod -Rf go-w "$mount_point" >/dev/null 2>&1 || true
if ! bless --folder "$mount_point" --openfolder "$mount_point" >/dev/null 2>&1; then
	bless --folder "$mount_point" >/dev/null 2>&1 || true
fi
rm -rf "$mount_point/.fseventsd" || true

hdiutil detach "$disk" >/dev/null
disk=""

rm -f "$root/Brian.dmg"
hdiutil convert "$workdir/Brian-rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$root/Brian.dmg" >/dev/null
echo "Built $root/Brian.dmg"
