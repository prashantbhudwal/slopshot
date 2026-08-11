import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let preferences = Preferences()
  private let hotKeys = HotKeyManager()
  private lazy var screenshots = ScreenshotCoordinator(
    preferences: preferences,
    promptDismissalDelayOverride: debugCaptureDismissalDelayOverride
  )
  private lazy var settings = SettingsWindowController(
    preferences: preferences,
    onShortcutChange: { [weak self] in self?.registerHotKeys(showingErrors: true) }
  )
  private lazy var updater = UpdateService()
  private var statusItem: NSStatusItem?

  private var debugCaptureDismissalDelayOverride: TimeInterval? {
    #if DEBUG
      CommandLine.arguments.contains("--capture-full")
        || CommandLine.arguments.contains("--prompt-delay-60") ? 60 : nil
    #else
      nil
    #endif
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    #if DEBUG
      if CommandLine.arguments.contains("--appearance-light") {
        NSApp.appearance = NSAppearance(named: .aqua)
      } else if CommandLine.arguments.contains("--appearance-dark") {
        NSApp.appearance = NSAppearance(named: .darkAqua)
      }
    #endif
    NSApp.setActivationPolicy(.accessory)
    configureMainMenu()
    configureMenuBar()
    hotKeys.onAction = { [weak self] action in
      switch action {
      case .fullScreen: self?.screenshots.capture(.fullScreen)
      case .selection: self?.screenshots.capture(.selection)
      case .chainedSelection: self?.captureChainedSelection()
      }
    }
    registerHotKeys(showingErrors: true)

    #if DEBUG
      if CommandLine.arguments.contains("--show-settings") {
        DispatchQueue.main.async { [weak self] in
          NSApp.activate(ignoringOtherApps: true)
          self?.settings.show()
        }
      }
      if let argumentIndex = CommandLine.arguments.firstIndex(of: "--show-prompt"),
        CommandLine.arguments.indices.contains(argumentIndex + 1)
      {
        let url = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
        DispatchQueue.main.async { [weak self] in
          NSApp.activate(ignoringOtherApps: true)
          self?.screenshots.captureExisting(url)
        }
      }
      if CommandLine.arguments.contains("--capture-full") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          self?.screenshots.capture(.fullScreen)
        }
      }
    #endif
  }

  func applicationWillTerminate(_ notification: Notification) {
    statusItem.map(NSStatusBar.system.removeStatusItem)
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

  private func configureMainMenu() {
    let mainMenu = NSMenu()
    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")

    editMenu.addItem(
      withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = editMenu.addItem(
      withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(
      withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(
      withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(
      withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(.separator())
    editMenu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    mainMenu.addItem(editItem)
    mainMenu.setSubmenu(editMenu, for: editItem)
    NSApp.mainMenu = mainMenu
  }

  private func configureMenuBar() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "viewfinder",
      accessibilityDescription: "SlopShot"
    )
    item.button?.toolTip = "SlopShot"

    let menu = NSMenu()
    menu.addItem(
      withTitle: "Capture All Displays", action: #selector(captureAllDisplays), keyEquivalent: "")
    menu.addItem(
      withTitle: "Capture Area or Window", action: #selector(captureSelection), keyEquivalent: "")
    menu.addItem(
      withTitle: "Capture Area + Chain", action: #selector(captureChainedSelection),
      keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
    menu.addItem(
      withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    menu.addItem(.separator())
    let quitItem = menu.addItem(
      withTitle: "Quit SlopShot", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    for menuItem in menu.items { menuItem.target = self }
    quitItem.target = NSApp
    item.menu = menu
    statusItem = item
  }

  private func registerHotKeys(showingErrors: Bool) {
    do {
      try hotKeys.register(
        fullScreen: preferences.fullScreenShortcut,
        selection: preferences.selectionShortcut,
        chainedSelection: preferences.chainedCaptureShortcut
      )
    } catch  where showingErrors {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Shortcut unavailable"
      alert.informativeText = error.localizedDescription
      alert.addButton(withTitle: "Settings")
      alert.addButton(withTitle: "OK")
      NSApp.activate(ignoringOtherApps: true)
      if alert.runModal() == .alertFirstButtonReturn { settings.show() }
    } catch {}
  }

  @objc private func captureAllDisplays() {
    screenshots.capture(.fullScreen)
  }

  @objc private func captureSelection() {
    screenshots.capture(.selection)
  }

  @objc private func captureChainedSelection() {
    guard let target = preferences.chainedTargetShortcut else {
      screenshots.capture(.selection)
      return
    }
    let captureShortcuts = [
      preferences.fullScreenShortcut,
      preferences.selectionShortcut,
      preferences.chainedCaptureShortcut,
    ]
    guard !captureShortcuts.contains(target) else {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Chained shortcut conflicts"
      alert.informativeText = "Choose a shortcut that is not used to capture screenshots."
      alert.addButton(withTitle: "Settings")
      NSApp.activate(ignoringOtherApps: true)
      alert.runModal()
      settings.show()
      return
    }
    screenshots.capture(.selection, chainedShortcut: target)
  }

  @objc private func showSettings() {
    settings.show()
  }

  @objc private func checkForUpdates() {
    updater.checkForUpdates()
  }
}
