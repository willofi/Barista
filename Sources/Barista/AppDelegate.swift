import AppKit
@preconcurrency import ApplicationServices
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate,
  ObservableObject
{
  @Published private(set) var collapsed = false
  @Published private(set) var isApplying = false
  @Published private(set) var temporarilyShowing = false
  @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
  @Published private(set) var statusMessage: String?
  @Published private(set) var hiddenAppCount = 0
  @Published private(set) var competingManagers: [String] = []
  @Published private(set) var loginEnabled = false
  @Published private(set) var loginMessage: String?
  @Published var iconStyle =
    StatusIconStyle(rawValue: UserDefaults.standard.string(forKey: "iconStyle") ?? "coffeeBean")
    ?? .coffeeBean
  {
    didSet {
      UserDefaults.standard.set(iconStyle.rawValue, forKey: "iconStyle")
      updateIcon()
    }
  }
  @Published var autoCollapse = UserDefaults.standard.bool(forKey: "autoCollapse") {
    didSet {
      UserDefaults.standard.set(autoCollapse, forKey: "autoCollapse")
      scheduleAutoCollapse()
    }
  }
  @Published var autoCollapseDelay =
    AutoCollapseDelay(rawValue: UserDefaults.standard.integer(forKey: "autoCollapseDelay"))
    ?? .fifteen
  {
    didSet {
      UserDefaults.standard.set(autoCollapseDelay.rawValue, forKey: "autoCollapseDelay")
      scheduleAutoCollapse()
    }
  }
  private var toggleItem: NSStatusItem!
  private var helpWindow: NSWindow?
  private var collapseTimer: Timer?
  private var interactionTimer: Timer?
  private var interactionWasBusy = false
  private let interactionMonitor: MenuInteractionMonitor
  var interactionBusyOverride: (() -> Bool)?
  private var localPointerMonitor: Any?
  private var restoreTimer: Timer?
  private var activationTimer: Timer?
  private let menu = NSMenu()
  private let visibility: any MenuVisibilityControlling
  private let accessibilityCheck: @MainActor () -> Bool
  private let scanItems: @Sendable ([MenuItemDiscovery.Candidate]) -> [MenuItemPosition]

  init(
    visibility: any MenuVisibilityControlling = MenuVisibilityBridge(),
    interactionMonitor: MenuInteractionMonitor = MenuInteractionMonitor(),
    accessibilityCheck: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
    scanItems: @escaping @Sendable ([MenuItemDiscovery.Candidate]) -> [MenuItemPosition] =
      MenuItemDiscovery.scan
  ) {
    self.visibility = visibility
    self.interactionMonitor = interactionMonitor
    self.accessibilityCheck = accessibilityCheck
    self.scanItems = scanItems
    super.init()
  }
  private let systemMenuArea = SystemMenuArea()
  private var hiddenIDs: Set<String> = []
  private var hiddenSystemIDs: Set<Int> = []
  private var ownBundleIDs: Set<String> {
    Set(
      [Bundle.main.bundleIdentifier, NSRunningApplication.current.bundleIdentifier].compactMap {
        $0
      }
    )
    .union(["dev.eden.barista"])
  }
  private var requestNumber = 0
  private var observers: [NSObjectProtocol] = []
  private var pointerMonitor: Any?
  private var keyMonitor: Any?
  private var localKeyMonitor: Any?
  private var menuBarDragWasCollapsed: Bool?
  private var layoutRefreshTask: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let appMenu = NSMenu()
    let root = NSMenuItem()
    root.submenu = appMenu
    let mainMenu = NSMenu()
    mainMenu.addItem(root)
    let quitItem = NSMenuItem(title: "Barista 종료", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    appMenu.addItem(quitItem)
    NSApp.mainMenu = mainMenu
    // One item: no separators, spacers, inflated widths, or global padding changes.
    toggleItem = NSStatusBar.system.statusItem(withLength: 22)
    toggleItem.autosaveName = "Barista.toggle.v1"
    toggleItem.behavior = []
    toggleItem.isVisible = true
    toggleItem.button?.target = self
    toggleItem.button?.action = #selector(toggleClicked)
    toggleItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    menu.delegate = self
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in
            guard let self else { return }
            self.refreshEnvironment()
            if self.collapsed && !self.temporarilyShowing { self.applyRestriction() }
          }
        })
    }
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.setCollapsed(false) }
      })
    // The private service affects Notification Center. Lift its restriction
    // before entering the clock/control area, then restore it after leaving.
    pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseUp,
    ]) {
      [weak self] event in
      self?.handlePointerEvent(event)
    }
    localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
    ]) { [weak self] event in
      self?.handlePointerEvent(event)
      return event
    }
    interactionTimer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.autoCollapse, !self.collapsed, !self.isApplying else { return }
        self.interactionMonitor.poll()
        self.refreshInteractionActivity()
      }
    }
    RunLoop.main.add(interactionTimer!, forMode: .common)
    keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleRestoreShortcut(event)
    }
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleRestoreShortcut(event)
      return event
    }
    refreshEnvironment()
    updateIcon()
    if !UserDefaults.standard.bool(forKey: "hasOpenedNativeVisibility") {
      UserDefaults.standard.set(true, forKey: "hasOpenedNativeVisibility")
      showHelp()
    }
  }

  @objc private func toggleClicked() {
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
      collapseTimer?.invalidate()
      rebuildMenu()
      toggleItem.menu = menu
      toggleItem.button?.performClick(nil)
      toggleItem.menu = nil
    } else if (event?.clickCount ?? 1) <= 1 {
      toggle()
    }
  }
  func menuDidClose(_ menu: NSMenu) {
    toggleItem.menu = nil
    scheduleAutoCollapse()
  }
  @objc func toggle() { setCollapsed(isApplying ? false : !collapsed) }

  func setCollapsed(_ value: Bool, closeSetupOnSuccess: Bool = false) {
    guard !value || !collapsed else {
      if closeSetupOnSuccess { helpWindow?.close() }
      return
    }
    layoutRefreshTask?.cancel()
    layoutRefreshTask = nil
    requestNumber += 1
    let request = requestNumber
    collapseTimer?.invalidate()
    restoreTimer?.invalidate()
    activationTimer?.invalidate()
    statusMessage = nil
    if !value {
      visibility.release()
      collapsed = false
      isApplying = false
      temporarilyShowing = false
      updateIcon()
      scheduleAutoCollapse()
      return
    }
    refreshEnvironment()
    guard visibility.isAvailable else {
      statusMessage = "이 macOS에서는 간격을 유지하는 숨김 방식이 지원되지 않습니다."
      showHelp()
      return
    }
    guard accessibilityGranted else {
      statusMessage = "시스템 설정에서 현재 Barista.app을 추가하고 손쉬운 사용 권한을 허용해 주세요. 이전 앱의 권한은 적용되지 않습니다."
      showHelp()
      return
    }
    guard let frame = toggleItem.button?.window?.frame, frame.width > 0, frame.width < 100,
      NSScreen.screens.contains(where: { frame.minX >= $0.frame.minX && frame.minX < $0.frame.maxX }
      )
    else {
      statusMessage = "Barista 아이콘 위치를 확인할 수 없습니다. 메뉴 막대에 배치한 뒤 다시 눌러 주세요."
      showHelp()
      return
    }
    isApplying = true
    let candidates = MenuItemDiscovery.candidates(excludingBundleIDs: ownBundleIDs)
    let boundary = frame.minX
    activationTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.requestNumber == request, self.isApplying else { return }
        self.setCollapsed(false)
        self.statusMessage = "응답이 지연되어 아이콘을 모두 표시했습니다. 다시 시도해 주세요."
      }
    }
    Task { @MainActor [weak self] in
      let scanItems = self?.scanItems ?? MenuItemDiscovery.scan
      let items = await Task.detached(priority: .userInitiated) {
        scanItems(candidates)
      }.value
      guard let self, self.requestNumber == request else { return }
      self.hiddenIDs = HiddenSelection.bundleIDs(items: items, boundary: boundary).subtracting(
        self.ownBundleIDs)
      self.hiddenSystemIDs = HiddenSelection.systemIDs(items: items, boundary: boundary)
      self.hiddenAppCount = self.hiddenIDs.count + self.hiddenSystemIDs.count
      guard !self.hiddenIDs.isEmpty || !self.hiddenSystemIDs.isEmpty else {
        self.isApplying = false
        self.activationTimer?.invalidate()
        self.statusMessage = "숨길 아이콘이 없습니다. ⌘ + 드래그로 Barista 아이콘 왼쪽에 배치해 주세요."
        self.showHelp()
        return
      }
      self.applyRestriction(request: request, closeSetupOnSuccess: closeSetupOnSuccess)
    }
  }
  private func applyRestriction(request: Int? = nil, closeSetupOnSuccess: Bool = false) {
    let currentRequest = request ?? requestNumber
    isApplying = true
    activationTimer?.invalidate()
    activationTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.requestNumber == currentRequest, self.isApplying else { return }
        self.setCollapsed(false)
        self.statusMessage = "응답이 지연되어 아이콘을 모두 표시했습니다. 다시 시도해 주세요."
        self.showHelp()
      }
    }
    let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    let alwaysVisible = ownBundleIDs.union([
      "com.apple.MenuBarAgent", "com.apple.UserNotificationCenter",
      "com.apple.notificationcenterui", "com.apple.loginwindow",
    ])
    let allowed = VisibilityPolicy.allowedBundleIDs(
      running: running, hidden: hiddenIDs, alwaysVisible: alwaysVisible)
    visibility.restrict(allowedBundleIDs: allowed, hiddenSystemIDs: hiddenSystemIDs) {
      [weak self] error in
      guard let self, self.requestNumber == currentRequest else { return }
      self.activationTimer?.invalidate()
      self.isApplying = false
      self.statusMessage = error
      self.collapsed = error == nil
      if error != nil { self.temporarilyShowing = false }
      self.updateIcon()
      if self.collapsed {
        if closeSetupOnSuccess { self.helpWindow?.close() }
        self.pointerMoved()
      } else {
        self.showHelp()
      }
    }
  }
  func handlePointerEvent(_ event: NSEvent, at location: CGPoint? = nil) {
    let point = location ?? NSEvent.mouseLocation
    let isInMenuBar = NSScreen.screens.contains {
      $0.frame.contains(point) && point.y >= $0.frame.maxY - NSStatusBar.system.thickness
    }
    if isInMenuBar && [.leftMouseDown, .rightMouseDown].contains(event.type) {
      // Own button/menu does not need an external popup ownership lookup.
      if toggleItem.button?.window?.frame.contains(point) != true {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        if let primary {
          interactionMonitor.menuBarClicked(
            at: CGPoint(x: point.x, y: primary.frame.maxY - point.y),
            candidates: MenuItemDiscovery.popupCandidates())
        }
      }
    }
    if event.type == .leftMouseDragged, event.modifierFlags.contains(.command),
      isInMenuBar, menuBarDragWasCollapsed == nil
    {
      // Read positions only after the complete layout is visible and the drag ends.
      let wasCollapsed = collapsed || isApplying
      setCollapsed(false)
      collapseTimer?.invalidate()
      menuBarDragWasCollapsed = wasCollapsed
    }
    if event.type == .leftMouseUp, let wasCollapsed = menuBarDragWasCollapsed {
      // Command may have been released before the mouse button.
      menuBarDragWasCollapsed = nil
      if wasCollapsed {
        let request = requestNumber
        layoutRefreshTask = Task { @MainActor [weak self] in
          do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
          guard let self, self.requestNumber == request else { return }
          self.setCollapsed(true)
        }
      } else {
        scheduleAutoCollapse()
      }
    }
    refreshInteractionActivity()
    pointerMoved()
  }

  private func pointerMoved() {
    guard collapsed else { return }
    let point = NSEvent.mouseLocation
    let nearSystemMenus = systemMenuArea.contains(
      point, excluding: toggleItem.button?.window?.frame, hiddenSystemIDs: hiddenSystemIDs)
    if nearSystemMenus {
      restoreTimer?.invalidate()
      if !temporarilyShowing {
        temporarilyShowing = true
        visibility.release()
        updateIcon()
      }
    } else if temporarilyShowing, restoreTimer?.isValid != true {
      restoreTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.collapsed else { return }
          self.temporarilyShowing = false
          self.applyRestriction()
        }
      }
    }
  }
  private func updateIcon() {
    guard toggleItem != nil else { return }
    toggleItem.isVisible = true
    toggleItem.button?.image = iconStyle.image(collapsed: collapsed)
    let title = collapsed ? "숨긴 아이콘 펼치기" : "아이콘 접기"
    toggleItem.button?.toolTip = "\(title) · 우클릭: 메뉴"
    toggleItem.button?.setAccessibilityLabel(title)
  }
  func refreshInteractionActivity() {
    guard autoCollapse, !collapsed, !isApplying else { return }
    let busy = interactionBusyOverride?() ?? interactionMonitor.isBusy()
    if busy {
      interactionWasBusy = true
      collapseTimer?.invalidate()
      collapseTimer = nil
    } else if interactionWasBusy {
      interactionWasBusy = false
      scheduleAutoCollapse()
    }
  }

  private func scheduleAutoCollapse() {
    collapseTimer?.invalidate()
    collapseTimer = nil
    guard autoCollapse, !collapsed, !isApplying, helpWindow?.isVisible != true, accessibilityCheck()
    else { return }
    collapseTimer = Timer.scheduledTimer(
      withTimeInterval: autoCollapseDelay.interval, repeats: false
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.helpWindow?.isVisible != true else { return }
        if self.interactionBusyOverride?() ?? self.interactionMonitor.isBusy() {
          self.interactionWasBusy = true
          return
        }
        guard NSEvent.pressedMouseButtons == 0, !NSEvent.modifierFlags.contains(.command),
          RunLoop.main.currentMode != .eventTracking
        else {
          self.scheduleAutoCollapse()
          return
        }
        self.setCollapsed(true)
      }
    }
  }
  func refreshAccessibilityPermission() {
    let granted = accessibilityCheck()
    let wasGranted = accessibilityGranted
    accessibilityGranted = granted
    if wasGranted && !granted {
      setCollapsed(false)
    } else if granted && !wasGranted {
      statusMessage = nil
      scheduleAutoCollapse()
    }
  }
  func refreshEnvironment() {
    refreshAccessibilityPermission()
    interactionMonitor.refresh()
    competingManagers = NSWorkspace.shared.runningApplications.compactMap { app in
      guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
        let name = app.localizedName
      else { return nil }
      let lower = name.lowercased()
      return lower.hasPrefix("bartender")
        || ["ice", "hidden bar", "menubarhide", "barbee"].contains(lower) ? name : nil
    }
    loginEnabled = SMAppService.mainApp.status == .enabled
  }
  func openAccessibilitySettings() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }
  func setLoginEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginMessage =
        SMAppService.mainApp.status == .requiresApproval ? "시스템 설정 → 일반 → 로그인 항목에서 허용해 주세요." : nil
    } catch { loginMessage = "로그인 설정을 변경하지 못했습니다: \(error.localizedDescription)" }
    refreshEnvironment()
  }
  private func rebuildMenu() {
    refreshEnvironment()
    menu.removeAllItems()
    if let statusMessage {
      let status = NSMenuItem(title: statusMessage, action: nil, keyEquivalent: "")
      status.isEnabled = false
      menu.addItem(status)
      menu.addItem(.separator())
    }
    addMenuItem(collapsed ? "숨긴 아이콘 펼치기" : "아이콘 접기", action: #selector(toggle))
    addMenuItem("설정…", action: #selector(showHelp))
    let styles = NSMenu(title: "아이콘 모양")
    styles.showsStateColumn = false
    for style in StatusIconStyle.allCases {
      let item = NSMenuItem(
        title: style.title, action: #selector(selectIconStyle(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = style.rawValue
      MenuChoiceRow.install(
        on: item, selected: iconStyle == style, icon: style.image(collapsed: true))
      styles.addItem(item)
    }
    let appearance = NSMenuItem(title: "아이콘 모양", action: nil, keyEquivalent: "")
    appearance.submenu = styles
    menu.addItem(appearance)
    let delays = NSMenu(title: "자동 접기")
    delays.showsStateColumn = false
    let never = NSMenuItem(
      title: "사용 안 함", action: #selector(disableAutoCollapse), keyEquivalent: "")
    never.target = self
    MenuChoiceRow.install(on: never, selected: !autoCollapse)
    delays.addItem(never)
    delays.addItem(.separator())
    for delay in AutoCollapseDelay.allCases {
      let item = NSMenuItem(
        title: "\(delay.rawValue)초 후 접기", action: #selector(selectAutoCollapseDelay(_:)),
        keyEquivalent: "")
      item.target = self
      item.tag = delay.rawValue
      MenuChoiceRow.install(on: item, selected: autoCollapse && autoCollapseDelay == delay)
      delays.addItem(item)
    }
    let timing = NSMenuItem(title: "자동 접기", action: nil, keyEquivalent: "")
    timing.submenu = delays
    menu.addItem(timing)
    menu.addItem(.separator())
    addMenuItem("종료 (아이콘 복원)", action: #selector(quit))
  }
  @discardableResult private func addMenuItem(_ title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
    return item
  }
  @objc private func disableAutoCollapse() { autoCollapse = false }
  @objc private func selectAutoCollapseDelay(_ sender: NSMenuItem) {
    guard let delay = AutoCollapseDelay(rawValue: sender.tag) else { return }
    autoCollapseDelay = delay
    autoCollapse = true
  }
  @objc private func selectIconStyle(_ sender: NSMenuItem) {
    guard let value = sender.representedObject as? String,
      let style = StatusIconStyle(rawValue: value)
    else { return }
    iconStyle = style
  }
  @objc func showHelp() {
    refreshEnvironment()
    collapseTimer?.invalidate()
    if helpWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
      window.title = "Barista"
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.contentView = NSHostingView(rootView: SettingsView(controller: self))
      window.center()
      helpWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    helpWindow?.makeKeyAndOrderFront(nil)
  }
  func finishSetup() { helpWindow?.close() }
  func windowWillClose(_ notification: Notification) {
    Task { @MainActor [weak self] in self?.scheduleAutoCollapse() }
  }
  private func handleRestoreShortcut(_ event: NSEvent) {
    if event.keyCode == 100 && event.modifierFlags.contains(.control) { setCollapsed(false) }
  }
  @objc private func quit() { NSApp.terminate(nil) }
  func applicationWillTerminate(_ notification: Notification) {
    layoutRefreshTask?.cancel()
    requestNumber += 1
    collapseTimer?.invalidate()
    restoreTimer?.invalidate()
    activationTimer?.invalidate()
    visibility.release()
    interactionTimer?.invalidate()
    interactionMonitor.stop()
    if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
    if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    for observer in observers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      NotificationCenter.default.removeObserver(observer)
    }
    if let toggleItem { NSStatusBar.system.removeStatusItem(toggleItem) }
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    setCollapsed(false)
    showHelp()
    return true
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    refreshEnvironment()
  }
}
