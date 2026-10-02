#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="${PWD}/build/Barista.app"
[[ -d "$APP" ]] || { print -u2 'Run scripts/build.sh first'; exit 1; }
/usr/bin/codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
MINIMUM=$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")
[[ "$MINIMUM" == '27.0' ]] || { print -u2 'Unexpected minimum macOS'; exit 1; }
[[ "$(/usr/bin/lipo -archs "$APP/Contents/MacOS/Barista")" == 'arm64' ]] || { print -u2 'Unexpected architecture'; exit 1; }
mkdir -p dist
ARCHIVE="Barista-${VERSION}-macos27-arm64.zip"
# ditto replaces the archive; never update an old ZIP in place.
rm -f "dist/$ARCHIVE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$ARCHIVE"
(cd dist && /usr/bin/shasum -a 256 "$ARCHIVE" > SHA256SUMS)
print "Release: ${PWD}/dist/$ARCHIVE"
