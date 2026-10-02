import AppKit
import ApplicationServices

struct MenuItemPosition: Sendable {
  let bundleID: String
  let x: CGFloat
}

enum HiddenSelection {
  /// macOS 27 applies visibility per app. Keep an app visible if any of its
  /// icons is on the visible side; never unexpectedly hide its other icon.
  static func bundleIDs(items: [MenuItemPosition], boundary: CGFloat) -> Set<String> {
    guard boundary.isFinite else { return [] }
    let groups = Dictionary(grouping: items, by: \.bundleID)
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
        app.activationPolicy != .prohibited,
        let id = app.bundleIdentifier, !id.hasPrefix("com.apple."),
        !excludingBundleIDs.contains(id)
      else { return nil }
      return Candidate(pid: app.processIdentifier, bundleID: id)
    }
  }

  static func scan(_ candidates: [Candidate]) -> [MenuItemPosition] {
    guard AXIsProcessTrusted() else { return [] }
    return candidates.flatMap { candidate -> [MenuItemPosition] in
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
      return items.map { item in
        var value: CFTypeRef?
        guard
          AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXValueGetTypeID()
        else {
          return MenuItemPosition(bundleID: candidate.bundleID, x: .nan)
        }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point) else {
          return MenuItemPosition(bundleID: candidate.bundleID, x: .nan)
        }
        return MenuItemPosition(bundleID: candidate.bundleID, x: point.x)
      }
    }
  }
}
