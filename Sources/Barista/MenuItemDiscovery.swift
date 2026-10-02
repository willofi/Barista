import AppKit
import ApplicationServices

struct MenuItemPosition: Sendable {
  let bundleID: String
  let x: CGFloat
  var systemID: Int? = nil
}

enum HiddenSelection {
  /// macOS 27 applies visibility per app. Keep an app visible if any of its
  /// icons is on the visible side; never unexpectedly hide its other icon.
  static func bundleIDs(items: [MenuItemPosition], boundary: CGFloat) -> Set<String> {
    guard boundary.isFinite else { return [] }
    let groups = Dictionary(grouping: items.filter { $0.systemID == nil }, by: \.bundleID)
    return Set(
      groups.compactMap { id, positions in
        positions.allSatisfy { $0.x.isFinite && $0.x < boundary } ? id : nil
      })
  }

  static func systemIDs(items: [MenuItemPosition], boundary: CGFloat) -> Set<Int> {
    guard boundary.isFinite else { return [] }
    let groups = Dictionary(grouping: items.filter { $0.systemID != nil }, by: { $0.systemID! })
    return Set(
      groups.compactMap { id, positions in
        positions.allSatisfy { $0.x.isFinite && $0.x < boundary } ? id : nil
      })
  }
}

enum MenuItemDiscovery {
  struct Candidate: Sendable {
    let pid: pid_t
    let bundleID: String
  }

  @MainActor
  static func candidates(excludingBundleIDs: Set<String> = []) -> [Candidate] {
    NSWorkspace.shared.runningApplications.compactMap { app in
      guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
        let id = app.bundleIdentifier, !excludingBundleIDs.contains(id),
        app.activationPolicy != .prohibited || SystemItemCatalog.menuOwnerBundleIDs.contains(id)
      else { return nil }
      return Candidate(pid: app.processIdentifier, bundleID: id)
    }
  }

  @MainActor
  static func popupCandidates() -> [Candidate] {
    let regular = candidates()
    let knownPIDs = Set(regular.map(\.pid))
    let systemHosts: Set<String> = [
      "com.apple.controlcenter", "com.apple.wifi.WiFiAgent",
      "com.apple.UserNotificationCenter", "com.apple.notificationcenterui",
    ]
    let additional = NSWorkspace.shared.runningApplications.compactMap { app -> Candidate? in
      guard !knownPIDs.contains(app.processIdentifier), let id = app.bundleIdentifier,
        systemHosts.contains(id)
      else { return nil }
      return Candidate(pid: app.processIdentifier, bundleID: id)
    }
    return regular + additional
  }

  /// Hit-test each owning app's extras bar; MenuBarAgent proxies are not app ownership.
  static func ownerPIDs(at point: CGPoint, candidates: [Candidate]) -> Set<pid_t> {
    guard AXIsProcessTrusted() else { return [] }
    let matches = ParallelMenuScan.run(
      candidates.filter { $0.bundleID != "com.apple.MenuBarAgent" }
    ) { candidate in
      let app = AXUIElementCreateApplication(candidate.pid)
      AXUIElementSetMessagingTimeout(app, 0.1)
      var bar: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &bar) == .success,
        let bar, CFGetTypeID(bar) == AXUIElementGetTypeID()
      else { return [] }
      var children: CFTypeRef?
      AXUIElementCopyAttributeValue(
        unsafeDowncast(bar, to: AXUIElement.self), kAXChildrenAttribute as CFString, &children)
      let items = children as? [AXUIElement] ?? []
      let hit = items.contains { item in
        AXUIElementSetMessagingTimeout(item, 0.1)
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard
          AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position)
            == .success,
          AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
          let position, let size, CFGetTypeID(position) == AXValueGetTypeID(),
          CFGetTypeID(size) == AXValueGetTypeID()
        else { return false }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
          AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions)
        else { return false }
        return CGRect(origin: origin, size: dimensions).contains(point)
      }
      return hit ? [.init(bundleID: candidate.bundleID, x: CGFloat(candidate.pid))] : []
    }
    let owners = Set(matches.map { pid_t($0.x) })
    if !owners.isEmpty { return owners }
    // Native controls are hosted by MenuBarAgent, while their popup may belong
    // to ControlCenter or a dedicated system agent. Match an identified native
    // control before allowing these related hosts; never allow every process.
    guard let host = candidates.first(where: { $0.bundleID == "com.apple.MenuBarAgent" }) else {
      return []
    }
    let app = AXUIElementCreateApplication(host.pid)
    AXUIElementSetMessagingTimeout(app, 0.1)
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success,
      let hit
    else { return [] }
    var identifier: CFTypeRef?
    AXUIElementCopyAttributeValue(hit, kAXIdentifierAttribute as CFString, &identifier)
    guard let name = identifier as? String,
      let systemID = SystemItemCatalog.identifier(for: name)
    else { return [] }
    var related: Set<String> = ["com.apple.MenuBarAgent", "com.apple.controlcenter"]
    if systemID == 6 { related.insert("com.apple.wifi.WiFiAgent") }
    if systemID == 4 { related.insert("com.apple.TextInputMenuAgent") }
    if systemID == 2 {
      related.formUnion(["com.apple.UserNotificationCenter", "com.apple.notificationcenterui"])
    }
    return Set(candidates.filter { related.contains($0.bundleID) }.map(\.pid))
  }

  static func scan(_ candidates: [Candidate]) -> [MenuItemPosition] {
    guard AXIsProcessTrusted() else { return [] }
    return ParallelMenuScan.run(candidates, scan: scanCandidate)
  }

  private static func scanCandidate(_ candidate: Candidate) -> [MenuItemPosition] {
    let app = AXUIElementCreateApplication(candidate.pid)
    AXUIElementSetMessagingTimeout(app, 0.2)
    var bar: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &bar) == .success,
      let bar, CFGetTypeID(bar) == AXUIElementGetTypeID()
    else { return [] }
    let element = unsafeDowncast(bar, to: AXUIElement.self)
    var children: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        == .success,
      let items = children as? [AXUIElement]
    else { return [] }
    let isSystemHost = candidate.bundleID == "com.apple.MenuBarAgent"
    let scannedItems =
      isSystemHost
      ? items
        + items.flatMap { item -> [AXUIElement] in
          var children: CFTypeRef?
          AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &children)
          return children as? [AXUIElement] ?? []
        } : items
    return scannedItems.compactMap { item -> MenuItemPosition? in
      var systemID: Int?
      if isSystemHost {
        var identifier: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifier)
        guard let name = identifier as? String,
          let mappedID = SystemItemCatalog.identifier(for: name)
        else { return nil }
        systemID = mappedID
      }
      var value: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &value) == .success,
        let value, CFGetTypeID(value) == AXValueGetTypeID()
      else {
        return MenuItemPosition(bundleID: candidate.bundleID, x: .nan, systemID: systemID)
      }
      var point = CGPoint.zero
      guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point) else {
        return MenuItemPosition(bundleID: candidate.bundleID, x: .nan, systemID: systemID)
      }
      return MenuItemPosition(bundleID: candidate.bundleID, x: point.x, systemID: systemID)
    }
  }
}

/// Bound concurrent AX requests so one slow process cannot delay every following process.
enum ParallelMenuScan {
  private final class Results: @unchecked Sendable {
    let lock = NSLock()
    var values: [[MenuItemPosition]]
    init(count: Int) { values = Array(repeating: [], count: count) }
    func set(_ value: [MenuItemPosition], at index: Int) {
      lock.withLock { values[index] = value }
    }
  }
  static func run(
    _ candidates: [MenuItemDiscovery.Candidate],
    scan: @escaping @Sendable (MenuItemDiscovery.Candidate) -> [MenuItemPosition]
  ) -> [MenuItemPosition] {
    guard !candidates.isEmpty else { return [] }
    let results = Results(count: candidates.count)
    let workers = min(8, candidates.count)
    DispatchQueue.concurrentPerform(iterations: workers) { worker in
      for index in stride(from: worker, to: candidates.count, by: workers) {
        results.set(scan(candidates[index]), at: index)
      }
    }
    return results.values.flatMap { $0 }
  }
}
