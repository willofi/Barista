#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 6 -target arm64-apple-macos27.0 -module-cache-path "${PWD}/.build/module-cache" \
  Sources/Barista/AutoCollapseDelay.swift Sources/Barista/MenuItemDiscovery.swift Sources/Barista/StatusIconStyle.swift Sources/Barista/CoffeeBeanMark.swift \
  Sources/Barista/MenuVisibilityBridge.swift Tests/LayoutChecks.swift -o .build/layout-checks
.build/layout-checks
/usr/bin/plutil -lint Resources/Info.plist

xcrun swiftc -swift-version 6 -target arm64-apple-macos27.0 -module-cache-path "${PWD}/.build/module-cache" \
  Sources/Barista/AutoCollapseDelay.swift Sources/Barista/AppDelegate.swift Sources/Barista/SettingsView.swift \
  Sources/Barista/StatusIconStyle.swift Sources/Barista/CoffeeBeanMark.swift \
  Sources/Barista/MenuItemDiscovery.swift Sources/Barista/MenuVisibilityBridge.swift \
  Sources/Barista/SystemMenuArea.swift Tests/SetupChecks.swift -o .build/setup-checks
.build/setup-checks
