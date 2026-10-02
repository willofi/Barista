import AppKit

/// Two smooth lobes leave an S-shaped negative space, legible even at menu-bar size.
enum CoffeeBeanMark {
  static func path() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: -4, y: 53))
    path.curve(
      to: NSPoint(x: -4, y: -53), controlPoint1: NSPoint(x: -58, y: 48),
      controlPoint2: NSPoint(x: -55, y: -48))
    path.curve(
      to: NSPoint(x: -8, y: 0), controlPoint1: NSPoint(x: -28, y: -25),
      controlPoint2: NSPoint(x: -18, y: -15))
    path.curve(
      to: NSPoint(x: -4, y: 53), controlPoint1: NSPoint(x: 5, y: 24),
      controlPoint2: NSPoint(x: 8, y: 32))
    path.close()
    path.move(to: NSPoint(x: 4, y: -53))
    path.curve(
      to: NSPoint(x: 4, y: 53), controlPoint1: NSPoint(x: 58, y: -48),
      controlPoint2: NSPoint(x: 55, y: 48))
    path.curve(
      to: NSPoint(x: 8, y: 0), controlPoint1: NSPoint(x: 28, y: 25),
      controlPoint2: NSPoint(x: 18, y: 15))
    path.curve(
      to: NSPoint(x: 4, y: -53), controlPoint1: NSPoint(x: -5, y: -24),
      controlPoint2: NSPoint(x: -8, y: -32))
    path.close()
    return path
  }
}
