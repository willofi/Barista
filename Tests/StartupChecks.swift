import AppKit
import Foundation

@MainActor
final class StartupVisibility: MenuVisibilityControlling {
  let isAvailable = true
  var configurations: [Set<String>] = []
  var systemConfigurations: [Set<Int>] = []
  var releases = 0
  func restrict(
    allowedBundleIDs: Set<String>, hiddenSystemIDs: Set<Int>,
    completion: @escaping @MainActor (String?) -> Void
  ) {
    configurations.append(allowedBundleIDs)
    systemConfigurations.append(hiddenSystemIDs)
    completion(nil)
  }
  func release() { releases += 1 }
}

final class StartupLayout: @unchecked Sendable {
  private let lock = NSLock()
  private var positions: [MenuItemPosition] = [.init(bundleID: "early-login-app", x: -100000)]
  private var scanCount = 0
  func clearIcons() { lock.withLock { positions.removeAll() } }
  func setLateIcon(x: CGFloat?) {
    lock.withLock {
      positions.removeAll { $0.bundleID == "com.apple.finder" }
      if let x { positions.append(.init(bundleID: "com.apple.finder", x: x)) }
    }
  }
  func addSystemIcon() {
    lock.withLock {
      positions.append(.init(bundleID: "com.apple.MenuBarAgent", x: -99999, systemID: 6))
    }
  }
  var scans: Int { lock.withLock { scanCount } }
  func scan(_ candidates: [MenuItemDiscovery.Candidate]) -> [MenuItemPosition] {
    lock.withLock {
      scanCount += 1
      let ids = Set(candidates.map(\.bundleID))
      return positions.filter { ids.contains($0.bundleID) }
    }
  }
}

@main
struct StartupChecks {
  @MainActor static let notifications = NotificationCenter()
  static let candidates: [MenuItemDiscovery.Candidate] = [
    .init(pid: 1, bundleID: "early-login-app"),
    .init(pid: 2, bundleID: "com.apple.finder"),
    .init(pid: 3, bundleID: "com.apple.MenuBarAgent"),
  ]
  @MainActor static func main() async {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    UserDefaults.standard.set(false, forKey: "autoCollapse")
    UserDefaults.standard.set(true, forKey: "hasOpenedNativeVisibility")
    let layout = StartupLayout()
    let visibility = StartupVisibility()
    let controller = makeController(layout, visibility)
    app.delegate = controller
    controller.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    controller.setCollapsed(true)
    await settle { controller.collapsed && !controller.isApplying }
    precondition(controller.hiddenAppCount == 1)

    // Actual workspace observer path: icon is ready after the initial collapse.
    layout.setLateIcon(x: -99999)
    notifications.post(
      name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    await settle { controller.hiddenAppCount == 2 && !controller.isApplying }
    precondition(controller.hiddenAppCount == 2,
      "RED: a late login icon on the hidden side remains visible after the app-launch notification")
    precondition(visibility.releases == 0, "Adding a login icon must not unfold existing hidden items")
    print("PASS: late login notification adds the left icon and preserves the existing hidden icon")

    // Replaying a real app object also exercises bundle identity on relaunch.
    if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
      layout.setLateIcon(x: 100000)
      notifications.post(
        name: NSWorkspace.didLaunchApplicationNotification, object: nil,
        userInfo: [NSWorkspace.applicationUserInfoKey: finder])
      try? await Task.sleep(for: .milliseconds(1800))
      precondition(controller.hiddenAppCount == 1,
        "A relaunched formerly hidden app on the right must become visible")
      precondition(visibility.configurations.last!.contains("com.apple.finder"))
      precondition(visibility.releases == 0,
        "Relaunch must release only the changed app, without unfolding existing hidden icons")
      print("PASS: a relaunched app is measured again and remains visible when restored on the right")
    }

    // An app may be running before its icon is ready, without another launch event.
    controller.setCollapsed(false)
    layout.setLateIcon(x: nil)
    controller.setCollapsed(true)
    await settle { controller.collapsed && !controller.isApplying }
    try? await Task.sleep(for: .milliseconds(1200))
    layout.setLateIcon(x: .nan)
    try? await Task.sleep(for: .milliseconds(1100))
    precondition(controller.hiddenAppCount == 1, "Unreadable positions must remain visible")
    var busy = true
    controller.interactionBusyOverride = { busy }
    layout.setLateIcon(x: -99999)
    try? await Task.sleep(for: .milliseconds(1100))
    precondition(controller.hiddenAppCount == 1, "Login refresh must wait while a menu is in use")
    busy = false
    await settle { controller.hiddenAppCount == 2 && !controller.isApplying }
    precondition(controller.hiddenAppCount == 2, "A delayed icon must be retried after the launch event")
    print("PASS: missing and unreadable login icons are retried when their positions become available")

    controller.setCollapsed(false)
    layout.setLateIcon(x: 100000)
    controller.setCollapsed(true)
    await settle { controller.collapsed && !controller.isApplying }
    let count = visibility.configurations.count
    notifications.post(
      name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    try? await Task.sleep(for: .milliseconds(1300))
    precondition(controller.hiddenAppCount == 1 && visibility.configurations.count == count + 1,
      "A late right-side icon must stay visible after refreshing the running-app allow list")
    layout.addSystemIcon()
    await settle { controller.hiddenAppCount == 2 && !controller.isApplying }
    precondition(visibility.systemConfigurations.last == [6], "Late system controls must also be discovered")
    print("PASS: right-side apps stay visible and a late left-side system control is discovered")

    controller.setCollapsed(false)
    let expandedCount = visibility.configurations.count
    layout.setLateIcon(x: -99999)
    notifications.post(
      name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    try? await Task.sleep(for: .milliseconds(1100))
    precondition(!controller.collapsed && visibility.configurations.count == expandedCount,
      "Explicit unfolding must cancel pending login refreshes")
    controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

    // Fresh process state with permission already granted: startup must arm the timer.
    UserDefaults.standard.set(true, forKey: "autoCollapse")
    UserDefaults.standard.set(3, forKey: "autoCollapseDelay")
    let startup = makeController(layout, StartupVisibility())
    app.delegate = startup
    startup.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    await settle(timeout: 4) { startup.collapsed && !startup.isApplying }
    precondition(startup.collapsed && startup.hiddenAppCount == 3,
      "Startup with existing permission must start automatic collapse and reconstruct selection")
    startup.autoCollapse = false
    startup.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    print("PASS: startup arms automatic collapse with existing permission and rebuilds all ready icons")

    UserDefaults.standard.set(true, forKey: "autoCollapse")
    let emptyLayout = StartupLayout()
    emptyLayout.clearIcons()
    let emptyStartup = makeController(emptyLayout, StartupVisibility())
    app.delegate = emptyStartup
    emptyStartup.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    try? await Task.sleep(for: .milliseconds(3300))
    precondition(!emptyStartup.collapsed && emptyStartup.statusMessage == nil,
      "An empty startup scan must retry quietly without opening settings")
    precondition(!app.windows.contains { $0.title == "Barista" && $0.isVisible },
      "Opening settings after an empty scan would block all later automatic attempts")
    emptyLayout.setLateIcon(x: -99999)
    await settle(timeout: 4) { emptyStartup.collapsed && !emptyStartup.isApplying }
    precondition(emptyStartup.collapsed && emptyStartup.hiddenAppCount == 1,
      "Startup must recover when its first scan had no icons at all")
    emptyStartup.autoCollapse = false
    emptyStartup.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    print("PASS: an empty first startup scan retries and hides the later first icon")
  }

  @MainActor static func makeController(_ layout: StartupLayout, _ visibility: StartupVisibility) -> AppDelegate {
    let controller = AppDelegate(
      visibility: visibility, accessibilityCheck: { true }, scanItems: layout.scan,
      discoverCandidates: { excluded in candidates.filter { !excluded.contains($0.bundleID) } },
      workspaceNotifications: notifications)
    controller.interactionBusyOverride = { false }
    // Desktop input belongs to the user; do not let their held Command key
    // alter this unattended startup timer regression.
    controller.inputBusyOverride = { false }
    return controller
  }
  @MainActor static func settle(timeout: Double = 2, _ condition: () -> Bool) async {
    for _ in 0..<Int(timeout * 100) {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
  }
}
