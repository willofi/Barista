import Darwin
// The private API signatures and allocation convention were verified against
// MenuBarHider (MIT, Saveliy Yudin). See Resources/ThirdPartyNotices.txt.
import Foundation

enum VisibilityPolicy {
  static func allowedBundleIDs(
    running: Set<String>, hidden: Set<String>, alwaysVisible: Set<String>
  ) -> Set<String> {
    running.subtracting(hidden).union(alwaysVisible)
  }
}

@objc private protocol VisibilityAssertion {
  @objc(activateWithConfiguration:completionHandler:)
  func activate(
    with configuration: AnyObject, completionHandler: @escaping @Sendable (NSError?) -> Void)
  func invalidate()
}

private final class VisibilityToken: @unchecked Sendable {
  let assertion: VisibilityAssertion
  init(_ assertion: VisibilityAssertion) { self.assertion = assertion }
}

@MainActor
protocol MenuVisibilityControlling {
  var isAvailable: Bool { get }
  func restrict(allowedBundleIDs: Set<String>, completion: @escaping @MainActor (String?) -> Void)
  func release()
}

@MainActor
final class MenuVisibilityBridge: MenuVisibilityControlling {
  private let classes: (assertion: NSObject.Type, configuration: NSObject.Type)?
  private var active: VisibilityToken?
  private var pending: VisibilityToken?
  private static let initializer = NSSelectorFromString(
    "initWithAllowedSystemItems:allowedBundleIdentifiers:")

  var isAvailable: Bool { classes != nil }

  init() {
    guard #available(macOS 27, *),
      dlopen(
        "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW)
        != nil,
      let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
      let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
      assertion.instancesRespond(
        to: #selector(VisibilityAssertion.activate(with:completionHandler:))),
      assertion.instancesRespond(to: #selector(VisibilityAssertion.invalidate)),
      configuration.instancesRespond(to: Self.initializer)
    else {
      classes = nil
      return
    }
    classes = (assertion, configuration)
  }

  func restrict(
    allowedBundleIDs bundleIDs: Set<String>, completion: @escaping @MainActor (String?) -> Void
  ) {
    guard let classes else {
      completion("이 macOS 버전에서는 간격을 유지하는 숨김 방식을 사용할 수 없습니다.")
      return
    }
    let allocated = (classes.configuration as AnyObject)
      .perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
    // Keep every known system item visible, including identifiers added by updates.
    let systemIDs = (0..<64).map { NSNumber(value: $0) } as NSArray
    guard
      let configuration = allocated?.perform(
        Self.initializer, with: systemIDs,
        with: bundleIDs.sorted() as NSArray)?.takeRetainedValue()
    else {
      completion("메뉴 막대 표시 설정을 만들지 못했습니다.")
      return
    }
    pending?.assertion.invalidate()
    let token = VisibilityToken(
      unsafeBitCast(classes.assertion.init(), to: VisibilityAssertion.self))
    pending = token
    token.assertion.activate(with: configuration) { [weak self, token] error in
      Task { @MainActor in
        guard let self, self.pending === token else { return }
        self.pending = nil
        if let error {
          token.assertion.invalidate()
          self.release()
          completion("숨기지 못했습니다: \(error.localizedDescription)")
        } else {
          self.active?.assertion.invalidate()
          self.active = token
          completion(nil)
        }
      }
    }
  }

  func release() {
    pending?.assertion.invalidate()
    pending = nil
    active?.assertion.invalidate()
    active = nil
  }
}
