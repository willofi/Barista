import AppKit

enum StatusIconStyle: String, CaseIterable, Identifiable, Sendable {
  case coffeeBean, chevron, dots
  case capsule = "fold"
  case circle

  var id: String { rawValue }

  var title: String {
    switch self {
    case .coffeeBean: "커피콩"
    case .chevron: "얇은 화살표"
    case .dots: "두 점"
    case .capsule: "캡슐"
    case .circle: "원형"
    }
  }

  /// A template image keeps the icon crisp and legible on light/dark menu bars.
  /// Drawing in points lets AppKit render at each display's backing scale.
  func image(collapsed: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
      NSColor.black.setStroke()
      NSColor.black.setFill()
      let path = NSBezierPath()
      path.lineWidth = 1.35
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      switch self {
      case .coffeeBean:
        NSGraphicsContext.saveGraphicsState()
        let transform = AffineTransform(translationByX: 8, byY: 8)
        var rotation = transform
        rotation.rotate(byDegrees: collapsed ? -35 : 35)
        rotation.scale(0.13)
        (rotation as NSAffineTransform).concat()
        CoffeeBeanMark.path().fill()
        NSGraphicsContext.restoreGraphicsState()
      case .chevron:
        let outer: CGFloat = collapsed ? 10 : 6
        let inner: CGFloat = collapsed ? 5.5 : 10.5
        path.move(to: NSPoint(x: outer, y: 3.5))
        path.line(to: NSPoint(x: inner, y: 8))
        path.line(to: NSPoint(x: outer, y: 12.5))
      case .dots:
        for offset: CGFloat in [5, 11] {
          let center = NSPoint(x: offset, y: 8)
          NSBezierPath(
            ovalIn: NSRect(
              x: center.x - 1.5, y: center.y - 1.5,
              width: 3, height: 3)
          ).fill()
        }
      case .capsule:
        path.appendRoundedRect(
          NSRect(x: 2, y: 4.5, width: 12, height: 7), xRadius: 3.5, yRadius: 3.5)
        // A small inset dot signals state without changing the silhouette.
        let dotX: CGFloat = collapsed ? 5.5 : 10.5
        NSBezierPath(ovalIn: NSRect(x: dotX - 1, y: 7, width: 2, height: 2)).fill()
      case .circle:
        path.appendOval(in: NSRect(x: 2, y: 2, width: 12, height: 12))
        path.move(to: NSPoint(x: 5, y: 8))
        path.line(to: NSPoint(x: 11, y: 8))
        if collapsed {
          path.move(to: NSPoint(x: 8, y: 5))
          path.line(to: NSPoint(x: 8, y: 11))
        }
      }
      path.stroke()
      return true
    }
    // MenuBarAgent draws status items in another process on macOS 27.
    // Send pixels, rather than a process-local NSCustomImageRep closure.
    let rendered = NSImage(size: image.size)
    for scale in [1, 2, 3] {
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 16 * scale, pixelsHigh: 16 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      NSGraphicsContext.saveGraphicsState()
      let context = NSGraphicsContext(bitmapImageRep: bitmap)!
      NSGraphicsContext.current = context
      context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
      image.draw(
        in: NSRect(origin: .zero, size: image.size),
        from: .zero, operation: .copy, fraction: 1)
      NSGraphicsContext.restoreGraphicsState()
      bitmap.size = image.size
      rendered.addRepresentation(bitmap)
    }
    rendered.isTemplate = true
    return rendered
  }
}
