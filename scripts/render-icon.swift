import AppKit

@main
struct IconRenderer {
  static func main() throws {
    let output = CommandLine.arguments[1]
    let sizes = [16, 32, 64, 128, 256, 512, 1024]
    for size in sizes {
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
      let scale = AffineTransform(scale: CGFloat(size) / 1024)
      (scale as NSAffineTransform).concat()
      let tile = NSBezierPath(
        roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 208, yRadius: 208)
      let shadow = NSShadow()
      shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
      shadow.shadowBlurRadius = 24
      shadow.shadowOffset = NSSize(width: 0, height: -10)
      shadow.set()
      NSColor(calibratedRed: 0.12, green: 0.23, blue: 0.21, alpha: 1).setFill()
      tile.fill()
      NSShadow().set()
      NSGradient(
        starting: NSColor(calibratedRed: 0.19, green: 0.34, blue: 0.29, alpha: 1),
        ending: NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.17, alpha: 1))!.draw(
          in: tile, angle: -70)
      let transform = NSAffineTransform()
      transform.translateX(by: 512, yBy: 512)
      transform.rotate(byDegrees: -35)
      transform.scale(by: 5.3)
      transform.concat()
      NSColor(calibratedRed: 0.96, green: 0.90, blue: 0.77, alpha: 1).setFill()
      CoffeeBeanMark.path().fill()
      NSGraphicsContext.restoreGraphicsState()
      try bitmap.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: "\(output)/\(size).png"))
    }
  }
}
