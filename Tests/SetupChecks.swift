import AppKit
import ApplicationServices

@MainActor
final class CloseCounter: NSObject {
  var count = 0
  @objc func closed(_ notification: Notification) { count += 1 }
}

@main
struct SetupChecks {
  @MainActor static func main() {
    guard !AXIsProcessTrusted() else {
      fatalError("This regression requires a process without Accessibility permission")
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = AppDelegate()
    app.delegate = controller
    controller.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    controller.showHelp()
    let counter = CloseCounter()
    NotificationCenter.default.addObserver(
      counter, selector: #selector(CloseCounter.closed(_:)), name: NSWindow.willCloseNotification,
      object: nil)
    controller.setCollapsed(true, closeSetupOnSuccess: true)
    precondition(counter.count == 0, "RED: failed collapse closed the setup window")
    precondition(!controller.collapsed && !controller.isApplying)
    precondition(controller.statusMessage != nil)
    precondition(app.windows.contains { $0.title == "Barista" && $0.isVisible })
    controller.finishSetup()
    precondition(
      counter.count == 1, "RED: Done must close settings without requiring collapse permission")
    precondition(!controller.collapsed && !controller.isApplying)
    precondition(!app.windows.contains { $0.title == "Barista" && $0.isVisible })
    controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    print("PASS: denied collapse keeps setup open and all icons visible")
  }
}
