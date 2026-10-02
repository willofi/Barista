#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="${PWD}/build/Barista.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache
zsh scripts/icon.sh
xcrun swiftc -swift-version 6 -O -target arm64-apple-macos27.0 \
  -module-cache-path "${PWD}/.build/module-cache" \
  Sources/Barista/*.swift -o "$APP/Contents/MacOS/Barista"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/ThirdPartyNotices.txt"
if [[ -n "${BARISTA_SIGNING_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --options runtime --timestamp --sign "$BARISTA_SIGNING_IDENTITY" "$APP"
else
  /usr/bin/codesign --force --sign - "$APP"
fi
/usr/bin/codesign --verify --deep --strict "$APP"
print "Built: $APP"
