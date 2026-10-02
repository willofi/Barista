// Coordinate conversion and MenuBarAgent hosting-group discovery are adapted
// from MenuBarHider (MIT, Saveliy Yudin); see ThirdPartyNotices.txt.
import AppKit
import ApplicationServices

@MainActor
final class SystemMenuArea {
  private var cachedRects: [CGRect] = []
  private var queriedAt = Date.distantPast
  private var cachedHiddenSystemIDs: Set<Int> = []

  func contains(_ point: CGPoint, excluding ownItem: CGRect?, hiddenSystemIDs: Set<Int> = [])
    -> Bool
  {
    if ownItem?.insetBy(dx: -4, dy: -4).contains(point) == true { return false }
    // Hidden clock/control-center slots must not act as invisible hover triggers.
    if hiddenSystemIDs.contains(2) && hiddenSystemIDs.contains(8) { return false }
    if hiddenSystemIDs != cachedHiddenSystemIDs {
      cachedHiddenSystemIDs = hiddenSystemIDs
      queriedAt = .distantPast
    }
    guard
      NSScreen.screens.contains(where: {
        point.y >= $0.frame.maxY - 40 && $0.frame.contains(point)
      })
    else { return false }
    if Date().timeIntervalSince(queriedAt) > 2 {
      cachedRects = readFrames(hiddenSystemIDs: hiddenSystemIDs)
      queriedAt = Date()
    }
    if !cachedRects.isEmpty {
      return cachedRects.contains { $0.insetBy(dx: -6, dy: -4).contains(point) }
    }
    // An AX miss should preserve access to system menus, without making a
    // normally right-aligned toggle immediately unhide everything itself.
    return NSScreen.screens.contains { screen in
      CGRect(x: screen.frame.maxX - 180, y: screen.frame.maxY - 40, width: 180, height: 40)
        .contains(point)
    }
  }

  private func readFrames(hiddenSystemIDs: Set<Int>) -> [CGRect] {
    guard
      let agent = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.MenuBarAgent"
      ).first,
      let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
        ?? NSScreen.screens.first
    else { return [] }
    let app = AXUIElementCreateApplication(agent.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.15)
    guard let value = read(app, kAXExtrasMenuBarAttribute),
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return [] }
    let bar = unsafeDowncast(value, to: AXUIElement.self)
    let groups = read(bar, kAXChildrenAttribute) as? [AXUIElement] ?? []
    let children =
      groups + groups.flatMap { read($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    let targetIDs = Set(
      [
        ("com.apple.menuextra.clock", 2), ("com.apple.menuextra.controlcenter", 8),
      ].filter { !hiddenSystemIDs.contains($0.1) }.map { $0.0 })
    return children.compactMap { item in
      guard let id = read(item, kAXIdentifierAttribute) as? String, targetIDs.contains(id),
        let position = read(item, kAXPositionAttribute),
        CFGetTypeID(position) == AXValueGetTypeID(),
        let dimensions = read(item, kAXSizeAttribute), CFGetTypeID(dimensions) == AXValueGetTypeID()
      else { return nil }
      var origin = CGPoint.zero
      var size = CGSize.zero
      guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
        AXValueGetValue(unsafeDowncast(dimensions, to: AXValue.self), .cgSize, &size),
        size.width > 0, size.height > 0
      else { return nil }
      return CGRect(
        x: origin.x, y: primary.frame.maxY - origin.y - size.height,
        width: size.width, height: size.height)
    }
  }

  private func read(_ item: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(item, attribute as CFString, &result) == .success
      ? result : nil
  }
}
