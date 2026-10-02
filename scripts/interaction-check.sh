#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 6 -target arm64-apple-macos27.0 -module-cache-path "${PWD}/.build/module-cache" \
  Sources/Barista/MenuItemDiscovery.swift Sources/Barista/SystemItemCatalog.swift \
  Sources/Barista/MenuInteractionMonitor.swift Tests/InteractionChecks.swift -o .build/interaction-checks
SWIFT_BACKTRACE=enable=no .build/interaction-checks
