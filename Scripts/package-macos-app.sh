#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release --product BrianDesktop

app="$root/Brian.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/.build/release/BrianDesktop" "$app/Contents/MacOS/BrianDesktop"
cp "$root/Scripts/Info.plist" "$app/Contents/Info.plist"
cp "$root/Scripts/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
chmod +x "$app/Contents/MacOS/BrianDesktop"

if command -v codesign >/dev/null 2>&1; then
	codesign --force --sign - "$app"
fi

echo "Built $app"
