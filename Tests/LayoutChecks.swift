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
    let bridge = MenuVisibilityBridge()
    print("Selection and icon checks passed. macOS visibility API available: \(bridge.isAvailable)")
    bridge.release()
  }
}
