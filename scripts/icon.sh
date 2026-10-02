#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/icon-png .build/AppIcon.iconset .build/module-cache
xcrun swiftc -swift-version 6 -module-cache-path "${PWD}/.build/module-cache" \
  Sources/Barista/CoffeeBeanMark.swift scripts/render-icon.swift -o .build/render-icon
.build/render-icon .build/icon-png
for size in 16 32 128 256 512; do
  cp ".build/icon-png/${size}.png" ".build/AppIcon.iconset/icon_${size}x${size}.png"
  double=$((size * 2))
  cp ".build/icon-png/${double}.png" ".build/AppIcon.iconset/icon_${size}x${size}@2x.png"
done
/usr/bin/iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
cp .build/icon-png/1024.png Resources/Barista.png
cp .build/icon-png/256.png Resources/Barista-preview.png
