import AppKit
import Foundation

@MainActor
final class RecordingVisibility: MenuVisibilityControlling {
  let isAvailable = true
  var configurations: [Set<String>] = []
  func restrict(allowedBundleIDs: Set<String>, completion: @escaping @MainActor (String?) -> Void) {
    configurations.append(allowedBundleIDs)
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
