import Foundation

enum AutoCollapseDelay: Int, CaseIterable, Identifiable, Sendable {
  case three = 3
  case five = 5
  case fifteen = 15
  case thirty = 30
  var id: Int { rawValue }
  var interval: TimeInterval { TimeInterval(rawValue) }
}
