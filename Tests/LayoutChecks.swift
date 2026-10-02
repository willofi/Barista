import AppKit

@main
struct LayoutChecks {
  @MainActor
  static func main() {
    let positions: [MenuItemPosition] = [
      .init(bundleID: "left", x: 100), .init(bundleID: "right", x: 300),
      .init(bundleID: "split", x: 110), .init(bundleID: "split", x: 310),
      .init(bundleID: "edge", x: 200), .init(bundleID: "unreadable", x: .nan),
      .init(bundleID: "partial", x: 150), .init(bundleID: "partial", x: .infinity),
    ]
    precondition(
      HiddenSelection.bundleIDs(items: positions, boundary: 200) == ["left"],
      "Only apps with every icon on the hidden side may disappear")
    precondition(HiddenSelection.bundleIDs(items: positions, boundary: .nan).isEmpty)
    precondition(HiddenSelection.bundleIDs(items: [], boundary: 200).isEmpty)
    precondition(
      HiddenSelection.bundleIDs(items: [.init(bundleID: "left-display", x: -500)], boundary: -100)
        == ["left-display"])
    for style in StatusIconStyle.allCases {
      for collapsed in [false, true] {
        let icon = style.image(collapsed: collapsed)
        precondition(icon.isTemplate && icon.size == NSSize(width: 16, height: 16))
        precondition(icon.tiffRepresentation != nil, "Every style must render in both states")
        precondition(
          icon.representations.allSatisfy { $0 is NSBitmapImageRep },
          "Menu-bar images must contain transferable pixels")
        precondition(icon.representations.count == 3)
        for case let bitmap as NSBitmapImageRep in icon.representations {
          var visiblePixels = 0
          for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
              if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { visiblePixels += 1 }
            }
          }
          precondition(visiblePixels > 5, "Every icon must remain visible after rasterization")
        }
      }
      precondition(StatusIconStyle(rawValue: style.rawValue) == style)
    }
    let dotStates = [false, true].map { StatusIconStyle.dots.image(collapsed: $0) }
    for scaleIndex in 0..<3 {
      let shown = dotStates[0].representations[scaleIndex] as! NSBitmapImageRep
      let hidden = dotStates[1].representations[scaleIndex] as! NSBitmapImageRep
      for y in 0..<shown.pixelsHigh {
        for x in 0..<shown.pixelsWide {
          let a = shown.colorAt(x: x, y: y)!.alphaComponent
          let b = hidden.colorAt(x: x, y: y)!.alphaComponent
          precondition(abs(a - b) < 0.01, "Two dots must remain horizontal in both states")
        }
      }
    }
    precondition(
      StatusIconStyle(rawValue: "fold") == .capsule, "Existing icon choice must migrate to capsule")
    let ownID = "dev.eden.barista"
    let allowed = VisibilityPolicy.allowedBundleIDs(
      running: [ownID, "hidden-app", "visible-app"],
      hidden: [ownID, "hidden-app", "com.apple.controlcenter"],
      alwaysVisible: [ownID, "com.apple.controlcenter"])
    precondition(allowed.contains(ownID), "RED: collapse can hide Barista's own control")
    precondition(allowed.contains("com.apple.controlcenter"))
    precondition(!allowed.contains("hidden-app") && allowed.contains("visible-app"))

    let systemPositions: [MenuItemPosition] = [
      .init(bundleID: "com.apple.MenuBarAgent", x: 100, systemID: 6),
      .init(bundleID: "com.apple.MenuBarAgent", x: 300, systemID: 0),
      .init(bundleID: "com.apple.MenuBarAgent", x: .nan, systemID: 2),
      .init(bundleID: "com.apple.MenuBarAgent", x: 120, systemID: 8),
    ]
    precondition(HiddenSelection.systemIDs(items: systemPositions, boundary: 200) == [6, 8])
    precondition(HiddenSelection.bundleIDs(items: systemPositions, boundary: 200).isEmpty)
    precondition(SystemItemCatalog.identifier(for: "com.apple.menuextra.wifi") == 6)
    precondition(SystemItemCatalog.identifier(for: "com.apple.menuextra.unknown") == nil)
    precondition(SystemItemCatalog.allAllowed.subtracting([6]).contains(0))
    let splitSystem =
      systemPositions + [
        MenuItemPosition(bundleID: "com.apple.MenuBarAgent", x: 350, systemID: 6)
      ]
    precondition(
      HiddenSelection.systemIDs(items: splitSystem, boundary: 200) == [8],
      "A system item spanning displays or both sides must remain visible")
    precondition(HiddenSelection.systemIDs(items: systemPositions, boundary: .nan).isEmpty)
    precondition(
      SystemItemCatalog.allAllowed.subtracting([6, 8]).contains(63),
      "Unknown system identifiers must remain allowed")
    let systemArea = SystemMenuArea()
    precondition(
      !systemArea.contains(.zero, excluding: nil, hiddenSystemIDs: [2, 8]),
      "Hidden system controls must not create ghost hover triggers")
    let candidates = (0..<16).map {
      MenuItemDiscovery.Candidate(pid: pid_t($0), bundleID: "app-\($0)")
    }
    let start = Date()
    let scanned = ParallelMenuScan.run(candidates) { candidate in
      Thread.sleep(forTimeInterval: 0.02)
      return [.init(bundleID: candidate.bundleID, x: CGFloat(candidate.pid))]
    }
    precondition(
      scanned.map(\.bundleID) == candidates.map(\.bundleID),
      "Parallel discovery must preserve every process and deterministic ordering")
    print(
      "16 simulated slow processes scanned in \(Date().timeIntervalSince(start)) seconds (sequential minimum: 0.32 seconds)"
    )
    let bridge = MenuVisibilityBridge()
    print("Selection and icon checks passed. macOS visibility API available: \(bridge.isAvailable)")
    bridge.release()
  }
}
