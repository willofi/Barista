import Foundation

/// MBSystemItemIdentifier values verified by MenuBarHider on macOS 27 (see ThirdPartyNotices).
/// Keep unknown identifiers allowed: guesses could hide an unrelated system control.
enum SystemItemCatalog {
  static let allAllowed = Set(0..<64)
  static let menuOwnerBundleIDs: Set<String> = [
    "com.apple.MenuBarAgent", "com.apple.systemuiserver", "com.apple.TextInputMenuAgent",
    "com.apple.Siri", "com.apple.Spotlight", "com.apple.ScreenTimeAgent",
    "com.apple.AirPlayUIAgent",
  ]
  static func identifier(for accessibilityID: String) -> Int? {
    switch accessibilityID {
    case "com.apple.menuextra.battery": 0
    case "com.apple.menuextra.bluetooth": 1
    case "com.apple.menuextra.clock": 2
    case "com.apple.menuextra.displays", "com.apple.menuextra.display": 3
    case "com.apple.menuextra.keyboard", "com.apple.menuextra.textinput": 4
    case "com.apple.menuextra.volume", "com.apple.menuextra.sound": 5
    case "com.apple.menuextra.wifi": 6
    case "com.apple.menuextra.screenmirroring", "com.apple.menuextra.airplay": 7
    case "com.apple.menuextra.controlcenter": 8
    default: nil
    }
  }
}
