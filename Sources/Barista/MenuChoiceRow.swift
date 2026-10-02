import AppKit

/// A full-width choice row. Selection lives in the row itself, never in a checkmark column.
@MainActor
final class MenuChoiceRow: NSView {
  private weak var item: NSMenuItem?
  private let selected: Bool
  private let icon: NSImage?
  private var hovered = false
  private var hoverTracking: NSTrackingArea?

  static func install(on item: NSMenuItem, selected: Bool, icon: NSImage? = nil) {
    item.state = .off
    item.image = nil
    item.attributedTitle = nil
    item.view = MenuChoiceRow(item: item, selected: selected, icon: icon)
  }

  private init(item: NSMenuItem, selected: Bool, icon: NSImage?) {
    self.item = item
    self.selected = selected
    self.icon = icon
    super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 32))
    autoresizingMask = [.width]
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(item.title)
    setAccessibilityValue(selected ? "선택됨" : "선택 안 됨")
  }

  required init?(coder: NSCoder) { nil }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTracking { removeTrackingArea(hoverTracking) }
    let tracking = NSTrackingArea(
      rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(tracking)
    hoverTracking = tracking
  }

  override func mouseEntered(with event: NSEvent) {
    hovered = true
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    hovered = false
    needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    activate()
  }
  override func accessibilityPerformPress() -> Bool {
    activate()
    return true
  }

  private func activate() {
    guard let item, item.isEnabled, let action = item.action else { return }
    item.menu?.cancelTracking()
    NSApp.sendAction(action, to: item.target, from: item)
  }

  override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

  override func draw(_ dirtyRect: NSRect) {
    guard let item else { return }
    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 6, yRadius: 6)
    if selected {
      NSColor.controlAccentColor.setFill()
      background.fill()
    } else if hovered || item.isHighlighted {
      NSColor.labelColor.withAlphaComponent(0.08).setFill()
      background.fill()
    }
    let foreground: NSColor = selected ? .selectedMenuItemTextColor : .labelColor
    let textX: CGFloat = icon == nil ? 14 : 40
    if let icon {
      // Tint the template explicitly so it also reverses inside the selected row.
      let tinted = NSImage(size: icon.size, flipped: false) { rect in
        icon.draw(in: rect)
        foreground.setFill()
        rect.fill(using: .sourceIn)
        return true
      }
      tinted.draw(in: NSRect(x: 14, y: (bounds.height - 16) / 2, width: 16, height: 16))
    }
    let label = NSAttributedString(
      string: item.title,
      attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: selected ? .medium : .regular),
        .foregroundColor: foreground,
      ])
    label.draw(at: NSPoint(x: textX, y: (bounds.height - label.size().height) / 2))
  }
}
