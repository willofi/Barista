import AppKit
import Foundation

@MainActor
final class RecordingVisibility: MenuVisibilityControlling {
  let isAvailable = true
  var configurations: [Set<String>] = []
  var systemConfigurations: [Set<Int>] = []
  func restrict(
    allowedBundleIDs: Set<String>, hiddenSystemIDs: Set<Int>,
    completion: @escaping @MainActor (String?) -> Void
  ) {
    configurations.append(allowedBundleIDs)
    systemConfigurations.append(hiddenSystemIDs)
    completion(nil)
  }
  func release() {}
}

final class MovingLayout: @unchecked Sendable {
  private let lock = NSLock()
  private var moved = false
  func moveAcrossBoundary(_ hidden: Bool = true) { lock.withLock { moved = hidden } }
  func scan(_ candidates: [MenuItemDiscovery.Candidate]) -> [MenuItemPosition] {
    lock.withLock {
      // The first item is always left. The second crosses the control after dragging.
      [
        MenuItemPosition(bundleID: "existing-left", x: -100000),
        MenuItemPosition(bundleID: "moved-item", x: moved ? -99999 : 100000),
      ]
    }
  }
}

@main
struct ReorderChecks {
  @MainActor static func main() async {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let layout = MovingLayout()
    let service = RecordingVisibility()
    let controller = AppDelegate(
      visibility: service, accessibilityCheck: { true }, scanItems: layout.scan)
    app.delegate = controller
    controller.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    controller.autoCollapse = false
    controller.setCollapsed(true)
    await settle { controller.collapsed && !controller.isApplying }
    precondition(controller.hiddenAppCount == 1, "The initial right-side item must stay visible")
    let drag = NSEvent.mouseEvent(
      with: .leftMouseDragged, location: .zero, modifierFlags: .command,
      timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    let screen = NSScreen.main!.frame
    let menuPoint = CGPoint(x: screen.midX, y: screen.maxY - 5)
    controller.handlePointerEvent(drag, at: menuPoint)
    layout.moveAcrossBoundary()
    let release = NSEvent.mouseEvent(
      with: .leftMouseUp, location: .zero, modifierFlags: [],
      timestamp: 1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
    controller.handlePointerEvent(release, at: menuPoint)
    await settle {
      controller.collapsed && controller.hiddenAppCount == 2 && !controller.isApplying
    }
    precondition(
      controller.hiddenAppCount == 2,
      "RED: moving an item to the hidden side must refresh the hidden set")
    precondition(
      service.configurations.count == 2, "Reorder must apply exactly one fresh configuration")
    controller.handlePointerEvent(drag, at: menuPoint)
    layout.moveAcrossBoundary(false)
    controller.handlePointerEvent(release, at: menuPoint)
    await settle {
      controller.collapsed && controller.hiddenAppCount == 1 && !controller.isApplying
    }
    precondition(
      controller.hiddenAppCount == 1,
      "Moving back to the visible side must remove the item from the hidden set")
    precondition(service.configurations.count == 3)

    // An ordinary Command-drag in a window must not alter menu-bar visibility.
    controller.handlePointerEvent(drag, at: CGPoint(x: screen.midX, y: screen.midY))
    controller.handlePointerEvent(release, at: CGPoint(x: screen.midX, y: screen.midY))
    try? await Task.sleep(for: .milliseconds(400))
    precondition(service.configurations.count == 3 && controller.collapsed)

    // Explicitly unfolding while a deferred refresh waits cancels that refresh.
    controller.handlePointerEvent(drag, at: menuPoint)
    controller.handlePointerEvent(release, at: menuPoint)
    controller.setCollapsed(false)
    try? await Task.sleep(for: .milliseconds(400))
    precondition(!controller.collapsed && service.configurations.count == 3)
    controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    let systemService = RecordingVisibility()
    let systemController = AppDelegate(
      visibility: systemService, accessibilityCheck: { true },
      scanItems: { _ in
        [
          .init(bundleID: "com.apple.MenuBarAgent", x: -100000, systemID: 6),
          .init(bundleID: "com.apple.MenuBarAgent", x: 100000, systemID: 0),
        ]
      })
    app.delegate = systemController
    systemController.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    systemController.autoCollapse = false
    systemController.setCollapsed(true)
    await settle { systemController.collapsed && !systemController.isApplying }
    precondition(
      systemController.collapsed && systemController.hiddenAppCount == 1,
      "A layout with only system icons on the left must collapse")
    precondition(
      systemService.systemConfigurations == [[6]],
      "Only left-side Wi-Fi must be removed from the system allow list")
    precondition(
      systemService.configurations.last!.contains("com.apple.MenuBarAgent"),
      "The status-item host must stay allowed")
    // Run the real timer path: an external popup outlives the configured delay.
    systemController.finishSetup()
    var interacting = true
    systemController.interactionBusyOverride = { interacting }
    systemController.setCollapsed(false)
    systemController.autoCollapseDelay = .three
    systemController.autoCollapse = true
    systemController.refreshInteractionActivity()
    try? await Task.sleep(for: .milliseconds(3200))
    precondition(
      !systemController.collapsed,
      "An external menu must stay expanded beyond the auto-collapse delay")
    interacting = false
    systemController.refreshInteractionActivity()
    try? await Task.sleep(for: .milliseconds(1500))
    precondition(
      !systemController.collapsed,
      "Ending interaction must restart the full delay, not reuse elapsed time")
    try? await Task.sleep(for: .milliseconds(1800))
    await settle { systemController.collapsed }
    precondition(systemController.collapsed, "Idle time must eventually collapse")
    systemController.setCollapsed(false)
    interacting = true
    systemController.refreshInteractionActivity()
    systemController.setCollapsed(true)
    await settle { systemController.collapsed }
    precondition(
      systemController.collapsed,
      "Explicit collapse must work even while the pointer or a popup is busy")
    systemController.autoCollapse = false
    print(
      "PASS: external interaction pauses collapse, idle restarts the full delay, manual collapse bypasses it"
    )
    systemController.applicationWillTerminate(
      Notification(name: NSApplication.willTerminateNotification))
    let menuMonitor = MenuInteractionMonitor(sample: {
      InteractionSnapshot(windows: [], focusedPopup: false)
    })
    let staleService = RecordingVisibility()
    let staleController = AppDelegate(
      visibility: staleService, interactionMonitor: menuMonitor,
      accessibilityCheck: { true }, scanItems: { _ in [.init(bundleID: "left", x: -100000)] })
    app.delegate = staleController
    staleController.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    staleController.finishSetup()
    staleController.interactionBusyOverride = {
      menuMonitor.isBusy(pointer: CGPoint(x: -100000, y: -100000))
    }
    staleController.autoCollapseDelay = .three
    staleController.autoCollapse = true
    menuMonitor.receiveMenuEvent(pid: 1519, token: 1_701_801_278, opened: true)
    staleController.setCollapsed(false)
    staleController.refreshInteractionActivity()
    try? await Task.sleep(for: .milliseconds(4000))
    precondition(
      staleController.collapsed && staleService.configurations.count == 1,
      "A captured stale Chrome menu event must recover and allow the real auto-collapse timer to finish"
    )
    staleController.autoCollapse = false
    staleController.applicationWillTerminate(
      Notification(name: NSApplication.willTerminateNotification))
    print("PASS: stale Chrome menu events recover through the real automatic-collapse timer")
    print(
      "PASS: Command-drag refreshes the hidden side after release, even when Command is released first"
    )
  }
  @MainActor static func settle(_ condition: () -> Bool) async {
    for _ in 0..<100 {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
  }
}
