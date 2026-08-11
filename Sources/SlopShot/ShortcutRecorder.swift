import AppKit
import ApplicationServices
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
  @Binding var shortcut: ShortcutDefinition
  let onChange: () -> Void

  func makeNSView(context: Context) -> ShortcutRecorderButton {
    let button = ShortcutRecorderButton()
    button.preservesModifierSides = false
    button.onShortcut = { value in
      guard let value else { return }
      shortcut = value
      onChange()
    }
    button.shortcut = shortcut
    return button
  }

  func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
    button.preservesModifierSides = false
    button.shortcut = shortcut
    button.onShortcut = { value in
      guard let value else { return }
      shortcut = value
      onChange()
    }
  }
}

struct OptionalShortcutRecorder: NSViewRepresentable {
  @Binding var shortcut: ShortcutDefinition?
  let onChange: () -> Void

  func makeNSView(context: Context) -> ShortcutRecorderButton {
    let button = ShortcutRecorderButton()
    button.allowsClearing = true
    button.preservesModifierSides = true
    button.capturesGlobally = true
    button.shortcut = shortcut
    button.onShortcut = { value in
      shortcut = value
      onChange()
    }
    return button
  }

  func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
    button.allowsClearing = true
    button.preservesModifierSides = true
    button.capturesGlobally = true
    button.shortcut = shortcut
    button.onShortcut = { value in
      shortcut = value
      onChange()
    }
  }
}

final class ShortcutRecorderButton: NSButton {
  var onShortcut: ((ShortcutDefinition?) -> Void)?
  var shortcut: ShortcutDefinition? = .fullScreen {
    didSet { if !isRecording { updateTitle() } }
  }
  var allowsClearing = false
  var preservesModifierSides = false
  var capturesGlobally = false
  private var isRecording = false
  private var captureMonitor: ShortcutCaptureMonitor?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    bezelStyle = .rounded
    font = .monospacedSystemFont(ofSize: 13, weight: .medium)
    lineBreakMode = .byTruncatingTail
    setContentHuggingPriority(.defaultLow, for: .horizontal)
    setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    target = self
    action = #selector(beginRecording)
    setButtonType(.momentaryPushIn)
  }

  required init?(coder: NSCoder) { nil }

  override var acceptsFirstResponder: Bool { true }

  @objc private func beginRecording() {
    if capturesGlobally {
      guard AXIsProcessTrusted() else {
        showAccessibilityHelp()
        return
      }
      let monitor = ShortcutCaptureMonitor { [weak self] event in
        self?.handleRecordedEvent(event)
      }
      guard monitor.start() else {
        NSSound.beep()
        return
      }
      captureMonitor = monitor
    }
    isRecording = true
    title = "Press keys"
    window?.makeFirstResponder(self)
  }

  override func keyDown(with event: NSEvent) {
    handleRecordedEvent(event)
  }

  private func handleRecordedEvent(_ event: NSEvent) {
    if event.keyCode == 53 {
      endRecording()
      return
    }
    if allowsClearing, event.keyCode == 51 || event.keyCode == 117 {
      shortcut = nil
      onShortcut?(nil)
      endRecording()
      return
    }
    let usefulModifiers = event.modifierFlags.intersection([
      .command, .option, .shift, .control, .function,
    ])
    guard !usefulModifiers.isEmpty, !(event.charactersIgnoringModifiers?.isEmpty ?? true) else {
      NSSound.beep()
      return
    }
    let newShortcut = ShortcutDefinition(
      event: event,
      preserveModifierSides: preservesModifierSides
    )
    shortcut = newShortcut
    onShortcut?(newShortcut)
    endRecording()
  }

  private func endRecording() {
    captureMonitor?.stop()
    captureMonitor = nil
    isRecording = false
    updateTitle()
    window?.makeFirstResponder(nil)
  }

  private func showAccessibilityHelp() {
    let alert = NSAlert()
    alert.messageText = "Allow Accessibility"
    alert.informativeText = "Required to record a shortcut without firing it."
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn,
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil, isRecording { endRecording() }
    super.viewWillMove(toWindow: newWindow)
  }

  private func updateTitle() {
    title = shortcut?.displayName ?? "Set shortcut"
  }
}

private final class ShortcutCaptureMonitor {
  private let onKeyDown: (NSEvent) -> Void
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var capturedKeyCode: CGKeyCode?

  init(onKeyDown: @escaping (NSEvent) -> Void) {
    self.onKeyDown = onKeyDown
  }

  deinit { stop() }

  func start() -> Bool {
    let mask =
      (CGEventMask(1) << CGEventType.keyDown.rawValue)
      | (CGEventMask(1) << CGEventType.keyUp.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, type, event, userInfo in
          guard let userInfo else { return Unmanaged.passUnretained(event) }
          let monitor = Unmanaged<ShortcutCaptureMonitor>.fromOpaque(userInfo)
            .takeUnretainedValue()
          return monitor.handle(type: type, event: event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else { return false }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    eventTap = tap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  func stop() {
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
    runLoopSource = nil
    eventTap = nil
    capturedKeyCode = nil
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
      return Unmanaged.passUnretained(event)
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    if type == .keyUp {
      if capturedKeyCode == keyCode {
        capturedKeyCode = nil
        return nil
      }
      return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown, let appKitEvent = NSEvent(cgEvent: event) else {
      return Unmanaged.passUnretained(event)
    }
    capturedKeyCode = keyCode
    onKeyDown(appKitEvent)
    return nil
  }
}
