import AppKit
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts

enum PhysicalModifier: String, Codable, CaseIterable, Sendable {
  case leftControl
  case rightControl
  case leftOption
  case rightOption
  case leftShift
  case rightShift
  case leftCommand
  case rightCommand
  case function

  var keyCode: CGKeyCode {
    switch self {
    case .leftControl: CGKeyCode(kVK_Control)
    case .rightControl: CGKeyCode(kVK_RightControl)
    case .leftOption: CGKeyCode(kVK_Option)
    case .rightOption: CGKeyCode(kVK_RightOption)
    case .leftShift: CGKeyCode(kVK_Shift)
    case .rightShift: CGKeyCode(kVK_RightShift)
    case .leftCommand: CGKeyCode(kVK_Command)
    case .rightCommand: CGKeyCode(kVK_RightCommand)
    case .function: CGKeyCode(kVK_Function)
    }
  }

  var eventFlag: CGEventFlags {
    switch self {
    case .leftControl, .rightControl: .maskControl
    case .leftOption, .rightOption: .maskAlternate
    case .leftShift, .rightShift: .maskShift
    case .leftCommand, .rightCommand: .maskCommand
    case .function: .maskSecondaryFn
    }
  }

  var displayName: String {
    switch self {
    case .leftControl: "L⌃"
    case .rightControl: "R⌃"
    case .leftOption: "L⌥"
    case .rightOption: "R⌥"
    case .leftShift: "L⇧"
    case .rightShift: "R⇧"
    case .leftCommand: "L⌘"
    case .rightCommand: "R⌘"
    case .function: "fn"
    }
  }
}

struct ShortcutDefinition: Codable, Equatable, Sendable {
  let keyCode: UInt32
  let carbonModifiers: UInt32
  let keyLabel: String
  let physicalModifiers: [PhysicalModifier]?

  static let fullScreen = ShortcutDefinition(
    keyCode: UInt32(kVK_ANSI_3),
    carbonModifiers: UInt32(cmdKey | optionKey),
    keyLabel: "3"
  )

  static let selection = ShortcutDefinition(
    keyCode: UInt32(kVK_ANSI_4),
    carbonModifiers: UInt32(cmdKey | optionKey),
    keyLabel: "4"
  )

  static let chainedSelection = ShortcutDefinition(
    keyCode: UInt32(kVK_ANSI_5),
    carbonModifiers: UInt32(cmdKey | optionKey),
    keyLabel: "5"
  )

  var displayName: String {
    if let physicalModifiers, !physicalModifiers.isEmpty {
      return physicalModifiers.map(\.displayName).joined() + keyLabel.uppercased()
    }

    var result = ""
    if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
    if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    return result + keyLabel.uppercased()
  }

  var keyboardShortcut: KeyboardShortcuts.Shortcut {
    KeyboardShortcuts.Shortcut(
      carbonKeyCode: Int(keyCode),
      carbonModifiers: Int(carbonModifiers)
    )
  }

  init(
    keyCode: UInt32,
    carbonModifiers: UInt32,
    keyLabel: String,
    physicalModifiers: [PhysicalModifier]? = nil
  ) {
    self.keyCode = keyCode
    self.carbonModifiers = carbonModifiers
    self.keyLabel = keyLabel
    self.physicalModifiers = physicalModifiers
  }

  init(event: NSEvent, preserveModifierSides: Bool = false) {
    keyCode = UInt32(event.keyCode)
    var modifiers: UInt32 = 0
    if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
    if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
    if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
    carbonModifiers = modifiers
    keyLabel = event.charactersIgnoringModifiers?.uppercased() ?? "?"
    physicalModifiers = preserveModifierSides ? Self.physicalModifiers(from: event) : nil
  }

  static func physicalModifiers(from event: NSEvent) -> [PhysicalModifier] {
    // AppKit includes device-specific bits that distinguish the two sides of each modifier.
    let raw = event.modifierFlags.rawValue
    var result: [PhysicalModifier] = []

    if event.modifierFlags.contains(.control) {
      if raw & 0x0000_0001 != 0 { result.append(.leftControl) }
      if raw & 0x0000_2000 != 0 { result.append(.rightControl) }
      if result.isEmpty { result.append(.leftControl) }
    }
    if event.modifierFlags.contains(.option) {
      let count = result.count
      if raw & 0x0000_0020 != 0 { result.append(.leftOption) }
      if raw & 0x0000_0040 != 0 { result.append(.rightOption) }
      if result.count == count { result.append(.leftOption) }
    }
    if event.modifierFlags.contains(.shift) {
      let count = result.count
      if raw & 0x0000_0002 != 0 { result.append(.leftShift) }
      if raw & 0x0000_0004 != 0 { result.append(.rightShift) }
      if result.count == count { result.append(.leftShift) }
    }
    if event.modifierFlags.contains(.command) {
      let count = result.count
      if raw & 0x0000_0008 != 0 { result.append(.leftCommand) }
      if raw & 0x0000_0010 != 0 { result.append(.rightCommand) }
      if result.count == count { result.append(.leftCommand) }
    }
    if event.modifierFlags.contains(.function) {
      result.append(.function)
    }
    return result
  }
}
