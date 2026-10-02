import AppKit
import Foundation

final class ProbeCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  private var snapshot = InteractionSnapshot(windows: [], focusedPopup: false)
  func setSnapshot(_ snapshot: InteractionSnapshot) { lock.withLock { self.snapshot = snapshot } }
  var count: Int { lock.withLock { value } }
  func sample() -> InteractionSnapshot {
    lock.withLock { value += 1 }
    Thread.sleep(forTimeInterval: 0.05)
    return lock.withLock { snapshot }
  }
}

@main
struct InteractionChecks {
  @MainActor static func main() async {
    var tracking = PopupTracking()
    tracking.begin(owners: [10], windows: [.init(id: 1, pid: 10)])
    tracking.update(windows: [.init(id: 1, pid: 10), .init(id: 2, pid: 20)])
    precondition(!tracking.isBusy, "An unrelated floating window must not pause auto-collapse")
    tracking.update(windows: [.init(id: 1, pid: 10), .init(id: 2, pid: 20), .init(id: 3, pid: 10)])
    precondition(tracking.isBusy, "The clicked app's new popup must pause auto-collapse")
    tracking.update(windows: [.init(id: 1, pid: 10), .init(id: 2, pid: 20)])
    precondition(
      !tracking.isBusy,
      "Closing the clicked popup must release busy state even if another app's window remains")
    tracking.update(windows: [.init(id: 5, pid: 10)])
    precondition(
      !tracking.isBusy, "A completed popup session must not track later windows from the same app")
    tracking.begin(owners: [20], windows: [.init(id: 2, pid: 20)])
    tracking.update(windows: [.init(id: 4, pid: 10), .init(id: 2, pid: 20)])
    precondition(!tracking.isBusy, "A new click must replace ownership and preserve its baseline")
    let counter = ProbeCounter()
    let monitor = MenuInteractionMonitor(sample: counter.sample)
    let outside = CGPoint(x: -100000, y: -100000)
    for _ in 0..<1000 { _ = monitor.isBusy(pointer: outside) }
    precondition(counter.count == 0, "Pointer checks must not perform external queries")
    for _ in 0..<100 { monitor.poll() }
    try? await Task.sleep(for: .milliseconds(150))
    precondition(counter.count == 1, "Only one background probe may run at once")
    for _ in 0..<1000 { _ = monitor.isBusy(pointer: outside) }
    precondition(counter.count == 1, "Cached pointer checks must not add probes")
    // Reproduce the captured Chrome state: opened notification, no matching
    // close, no visible popup or focused menu, pointer away from the menu bar.
    monitor.receiveMenuEvent(pid: 1519, token: 1_701_801_278, opened: true)
    precondition(monitor.isBusy(pointer: outside), "Opening a menu must pause immediately")
    try? await Task.sleep(for: .milliseconds(700))
    monitor.poll()
    try? await Task.sleep(for: .milliseconds(150))
    precondition(
      !monitor.isBusy(pointer: outside),
      "RED: a lost menu-close notification must not block automatic collapse forever")
    counter.setSnapshot(
      InteractionSnapshot(windows: [.init(id: 8, pid: 1519, isMenu: true)], focusedPopup: false))
    monitor.receiveMenuEvent(pid: 1519, token: 1, opened: true)
    try? await Task.sleep(for: .milliseconds(700))
    monitor.poll()
    try? await Task.sleep(for: .milliseconds(150))
    precondition(
      monitor.isBusy(pointer: outside), "A visible menu must remain busy beyond the event grace")
    monitor.receiveMenuEvent(pid: 1519, token: 2, opened: false)
    monitor.poll()
    try? await Task.sleep(for: .milliseconds(150))
    precondition(
      monitor.isBusy(pointer: outside),
      "A mismatched close must not dismiss an actually visible menu")
    counter.setSnapshot(
      InteractionSnapshot(windows: [.init(id: 9, pid: 1519)], focusedPopup: false))
    monitor.poll()
    try? await Task.sleep(for: .milliseconds(150))
    precondition(
      !monitor.isBusy(pointer: outside),
      "Mismatched close records must expire after the menu disappears; an ordinary floating window must not retain them"
    )
    counter.setSnapshot(InteractionSnapshot(windows: [], focusedPopup: true))
    monitor.poll()
    try? await Task.sleep(for: .milliseconds(150))
    precondition(
      monitor.isBusy(pointer: outside),
      "A focused menu or popover must pause even without a window record")
    monitor.stop()
    print(
      "PASS: popup ownership excludes unrelated windows; pointer checks use cached state; probes do not overlap"
    )
  }
}
