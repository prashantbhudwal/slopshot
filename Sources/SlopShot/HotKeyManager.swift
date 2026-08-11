import Foundation
import KeyboardShortcuts

@MainActor
extension KeyboardShortcuts.Name {
  fileprivate static let slopShotFullScreen = Self("slopShotFullScreen")
  fileprivate static let slopShotSelection = Self("slopShotSelection")
  fileprivate static let slopShotChainedSelection = Self("slopShotChainedSelection")
}

@MainActor
final class HotKeyManager {
  enum Action: UInt32 {
    case fullScreen = 1
    case selection = 2
    case chainedSelection = 3
  }

  enum RegistrationError: LocalizedError {
    case duplicate

    var errorDescription: String? {
      switch self {
      case .duplicate: "Each capture action needs a different shortcut."
      }
    }
  }

  var onAction: ((Action) -> Void)?

  init() {
    KeyboardShortcuts.onKeyDown(for: .slopShotFullScreen) { [weak self] in
      self?.onAction?(.fullScreen)
    }
    KeyboardShortcuts.onKeyDown(for: .slopShotSelection) { [weak self] in
      self?.onAction?(.selection)
    }
    KeyboardShortcuts.onKeyDown(for: .slopShotChainedSelection) { [weak self] in
      self?.onAction?(.chainedSelection)
    }
  }

  func register(
    fullScreen: ShortcutDefinition,
    selection: ShortcutDefinition,
    chainedSelection: ShortcutDefinition
  ) throws {
    let shortcuts = [
      fullScreen.keyboardShortcut,
      selection.keyboardShortcut,
      chainedSelection.keyboardShortcut,
    ]
    guard Set(shortcuts).count == shortcuts.count else { throw RegistrationError.duplicate }

    KeyboardShortcuts.setShortcut(shortcuts[0], for: .slopShotFullScreen)
    KeyboardShortcuts.setShortcut(shortcuts[1], for: .slopShotSelection)
    KeyboardShortcuts.setShortcut(shortcuts[2], for: .slopShotChainedSelection)
  }
}
