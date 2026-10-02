import AppKit
import ApplicationServices

/// Menu tracking in another process does not put Barista's run loop in eventTracking mode.
/// Observe external menus and watch transient windows created by a menu-bar click.
@MainActor
final class MenuInteractionMonitor {
  private var observers: [pid_t: AXObserver] = [:]
  private var openMenus: [pid_t: Set<CFHashCode>] = [:]
  private var menuOpenedAt: [pid_t: Date] = [:]
  private var visibleMenu = false
  private var popupTracking = PopupTracking()
  private var clickGeneration = 0
  private var clickPending = false
  private var probePending = false
  private var focusedPopup = false
  private var clickedAt = Date.distantPast
  private let sample: @Sendable () -> InteractionSnapshot

  init(
    sample: @escaping @Sendable () -> InteractionSnapshot = {
      InteractionSnapshot(
        windows: MenuInteractionMonitor.windows(),
        focusedPopup: MenuInteractionMonitor.focusedMenuOrPopover())
    }
  ) { self.sample = sample }

  func refresh() {
    guard AXIsProcessTrusted() else {
      stop()
      return
    }
    let pids = Set(MenuItemDiscovery.candidates().map(\.pid))
    for pid in Array(observers.keys) where !pids.contains(pid) {
      CFRunLoopRemoveSource(
        CFRunLoopGetMain(), AXObserverGetRunLoopSource(observers.removeValue(forKey: pid)!),
        .commonModes)
      openMenus.removeValue(forKey: pid)
      menuOpenedAt.removeValue(forKey: pid)
    }
    for pid in pids where observers[pid] == nil {
      var observer: AXObserver?
      guard
        AXObserverCreate(
          pid,
          { _, element, notification, context in
            guard let context else { return }
            MainActor.assumeIsolated {
              let monitor = Unmanaged<MenuInteractionMonitor>.fromOpaque(context)
                .takeUnretainedValue()
              var pid: pid_t = 0
              guard AXUIElementGetPid(element, &pid) == .success else { return }
              monitor.receiveMenuEvent(
                pid: pid, token: CFHash(element),
                opened: notification as String == kAXMenuOpenedNotification as String)
            }
          }, &observer) == .success, let observer
      else { continue }
      let element = AXUIElementCreateApplication(pid)
      let context = Unmanaged.passUnretained(self).toOpaque()
      AXObserverAddNotification(observer, element, kAXMenuOpenedNotification as CFString, context)
      AXObserverAddNotification(observer, element, kAXMenuClosedNotification as CFString, context)
      CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
      observers[pid] = observer
    }
  }

  func receiveMenuEvent(pid: pid_t, token: CFHashCode, opened: Bool) {
    if opened {
      openMenus[pid, default: []].insert(token)
      menuOpenedAt[pid] = Date()
    } else {
      openMenus[pid]?.remove(token)
      if openMenus[pid]?.isEmpty == true {
        openMenus.removeValue(forKey: pid)
        menuOpenedAt.removeValue(forKey: pid)
      }
    }
  }

  func menuBarClicked(at point: CGPoint, candidates: [MenuItemDiscovery.Candidate]) {
    clickGeneration += 1
    let generation = clickGeneration
    clickPending = true
    let baseline = Self.windows()
    // AX and process ownership resolution run off the UI thread.
    Task { [weak self] in
      let owners = await Task.detached {
        MenuItemDiscovery.ownerPIDs(at: point, candidates: candidates)
      }.value
      guard let self, generation == self.clickGeneration else { return }
      self.clickPending = false
      self.popupTracking.begin(owners: owners, windows: baseline)
      self.clickedAt = Date()
      self.poll()
    }
  }

  /// Called only by the bounded periodic sampler, never by mouse-move callbacks.
  func poll() {
    guard !probePending else { return }
    probePending = true
    let generation = clickGeneration
    let sample = self.sample
    Task { [weak self] in
      let snapshot = await Task.detached { sample() }.value
      guard let self else { return }
      self.probePending = false
      guard generation == self.clickGeneration else { return }
      self.popupTracking.update(windows: snapshot.windows)
      if !self.popupTracking.isBusy && Date().timeIntervalSince(self.clickedAt) >= 0.5 {
        self.popupTracking = PopupTracking()
      }
      self.focusedPopup = snapshot.focusedPopup
      self.visibleMenu = snapshot.windows.contains { $0.isMenu }
      // AX close notifications can be missing or refer to a different element.
      // Keep live menus indefinitely, but discard old events once visual and
      // focused activity have both ended. The grace covers asynchronous creation.
      if !self.focusedPopup && !self.visibleMenu && !self.popupTracking.isBusy {
        let expired = self.menuOpenedAt.filter { Date().timeIntervalSince($0.value) >= 0.5 }.keys
        for pid in expired {
          self.openMenus.removeValue(forKey: pid)
          self.menuOpenedAt.removeValue(forKey: pid)
        }
      }
    }
  }

  func isBusy(pointer: CGPoint = NSEvent.mouseLocation) -> Bool {
    if NSScreen.screens.contains(where: {
      $0.frame.contains(pointer) && pointer.y >= $0.frame.maxY - NSStatusBar.system.thickness
    }) {
      return true
    }
    return !openMenus.isEmpty || clickPending || popupTracking.isBusy || focusedPopup || visibleMenu
      || Date().timeIntervalSince(clickedAt) < 0.5
  }

  nonisolated private static func windows() -> [InteractionWindow] {
    let windows =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []
    return windows.compactMap { window in
      guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
        let id = window[kCGWindowNumber as String] as? Int,
        let level = window[kCGWindowLayer as String] as? Int, level > 0,
        let bounds = window[kCGWindowBounds as String] as? NSDictionary,
        let rect = CGRect(dictionaryRepresentation: bounds),
        rect.height > 32 || level == Int(CGWindowLevelForKey(.popUpMenuWindow))
      else { return nil }
      return InteractionWindow(
        id: id, pid: pid, isMenu: level == Int(CGWindowLevelForKey(.popUpMenuWindow)))
    }
  }

  nonisolated private static func focusedMenuOrPopover() -> Bool {
    guard AXIsProcessTrusted() else { return false }
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.05)
    // Tracking a native NSMenu need not replace AXFocusedUIElement. Its
    // highlighted menu-bar item supplies independent evidence of an open menu.
    if selectedApplicationMenu(system: system) { return true }
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)
        == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return false }
    var element = unsafeDowncast(value, to: AXUIElement.self)
    let deadline = Date().addingTimeInterval(0.08)
    for _ in 0..<8 {
      guard Date() < deadline else { break }
      AXUIElementSetMessagingTimeout(element, 0.025)
      var role: CFTypeRef?
      AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
      if let role = role as? String,
        [kAXMenuRole as String, kAXMenuItemRole as String, kAXPopoverRole as String].contains(role)
      {
        return true
      }
      if role as? String == kAXWindowRole as String { return false }
      var parent: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
        let parent, CFGetTypeID(parent) == AXUIElementGetTypeID()
      else { break }
      element = unsafeDowncast(parent, to: AXUIElement.self)
    }
    return false
  }

  nonisolated private static func selectedApplicationMenu(system: AXUIElement) -> Bool {
    var application: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        system, kAXFocusedApplicationAttribute as CFString, &application) == .success,
      let application, CFGetTypeID(application) == AXUIElementGetTypeID()
    else { return false }
    let app = unsafeDowncast(application, to: AXUIElement.self)
    AXUIElementSetMessagingTimeout(app, 0.025)
    var bar: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success,
      let bar, CFGetTypeID(bar) == AXUIElementGetTypeID()
    else { return false }
    let menuBar = unsafeDowncast(bar, to: AXUIElement.self)
    var selected: CFTypeRef?
    AXUIElementCopyAttributeValue(menuBar, kAXSelectedChildrenAttribute as CFString, &selected)
    if let selected = selected as? [AXUIElement], !selected.isEmpty { return true }
    var children: CFTypeRef?
    AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &children)
    let deadline = Date().addingTimeInterval(0.1)
    for item in (children as? [AXUIElement] ?? []).prefix(16) {
      guard Date() < deadline else { break }
      AXUIElementSetMessagingTimeout(item, 0.015)
      var selected: CFTypeRef?
      AXUIElementCopyAttributeValue(item, kAXSelectedAttribute as CFString, &selected)
      if (selected as? NSNumber)?.boolValue == true { return true }
    }
    return false
  }

  func stop() {
    for observer in observers.values {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    observers.removeAll()
    openMenus.removeAll()
    menuOpenedAt.removeAll()
    visibleMenu = false
    clickGeneration += 1
    clickPending = false
    focusedPopup = false
    clickedAt = .distantPast
    popupTracking = PopupTracking()
  }
}

struct InteractionWindow: Sendable {
  let id: Int
  let pid: pid_t
  var isMenu = false
}

/// A popup from a different process must never extend this click's busy state.
struct PopupTracking {
  private var owners: Set<pid_t> = []
  private var baseline: Set<Int> = []
  private var tracked: Set<Int> = []
  var isBusy: Bool { !tracked.isEmpty }
  mutating func begin(owners: Set<pid_t>, windows: [InteractionWindow]) {
    self.owners = owners
    baseline = Set(windows.filter { owners.contains($0.pid) }.map(\.id))
    tracked.removeAll()
  }
  mutating func update(windows: [InteractionWindow]) {
    let wasBusy = isBusy
    let matching = Set(windows.filter { owners.contains($0.pid) }.map(\.id))
    tracked.formUnion(matching.subtracting(baseline))
    tracked.formIntersection(matching)
    if wasBusy && tracked.isEmpty {
      owners.removeAll()
      baseline.removeAll()
    }
  }
}

struct InteractionSnapshot: Sendable {
  let windows: [InteractionWindow]
  let focusedPopup: Bool
}
