import ApplicationServices
import Carbon.HIToolbox
import Foundation

@MainActor
enum ShortcutEmitter {
  static func requestAccessibility() -> Bool {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  @discardableResult
  static func post(_ shortcut: ShortcutDefinition) -> Bool {
    guard requestAccessibility(), let source = CGEventSource(stateID: .hidSystemState) else {
      return false
    }

    let physicalModifiers = shortcut.physicalModifiers ?? defaultPhysicalModifiers(for: shortcut)
    var activeFlags: CGEventFlags = []
    var delay = 0.0

    for modifier in physicalModifiers {
      activeFlags.insert(modifier.eventFlag)
      guard let event = keyboardEvent(source: source, keyCode: modifier.keyCode, down: true) else {
        return false
      }
      event.flags = activeFlags
      post(event, after: delay)
      delay += 0.012
    }

    guard
      let keyDown = keyboardEvent(
        source: source,
        keyCode: CGKeyCode(shortcut.keyCode),
        down: true
      ),
      let keyUp = keyboardEvent(
        source: source,
        keyCode: CGKeyCode(shortcut.keyCode),
        down: false
      )
    else { return false }

    keyDown.flags = activeFlags
    keyUp.flags = activeFlags
    post(keyDown, after: delay)
    delay += 0.025
    post(keyUp, after: delay)
    delay += 0.012

    var heldModifiers = physicalModifiers
    for modifier in physicalModifiers.reversed() {
      heldModifiers.removeLast()
      activeFlags = eventFlags(for: heldModifiers)
      guard let event = keyboardEvent(source: source, keyCode: modifier.keyCode, down: false) else {
        return false
      }
      event.flags = activeFlags
      post(event, after: delay)
      delay += 0.012
    }
    return true
  }

  private static func keyboardEvent(
    source: CGEventSource,
    keyCode: CGKeyCode,
    down: Bool
  ) -> CGEvent? {
    CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
  }

  private static func post(_ event: CGEvent, after delay: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      event.post(tap: .cghidEventTap)
    }
  }

  private static func defaultPhysicalModifiers(
    for shortcut: ShortcutDefinition
  ) -> [PhysicalModifier] {
    var result: [PhysicalModifier] = []
    if shortcut.carbonModifiers & UInt32(controlKey) != 0 { result.append(.leftControl) }
    if shortcut.carbonModifiers & UInt32(optionKey) != 0 { result.append(.leftOption) }
    if shortcut.carbonModifiers & UInt32(shiftKey) != 0 { result.append(.leftShift) }
    if shortcut.carbonModifiers & UInt32(cmdKey) != 0 { result.append(.leftCommand) }
    return result
  }

  private static func eventFlags(for modifiers: [PhysicalModifier]) -> CGEventFlags {
    modifiers.reduce(into: CGEventFlags()) { flags, modifier in
      flags.insert(modifier.eventFlag)
    }
  }
}
