import Foundation
import ServiceManagement
import SlopShotCore

@MainActor
final class Preferences: ObservableObject {
  private enum Key {
    static let fullScreenShortcut = "fullScreenShortcut"
    static let selectionShortcut = "selectionShortcut"
    static let chainedCaptureShortcut = "chainedCaptureShortcut"
    static let chainedTargetShortcut = "chainedTargetShortcut"
    static let visualPrompt = "visualPrompt"
    static let promptSize = "promptSize"
    static let autoSaveDelay = "autoSaveDelay"
    static let showAutoSaveCountdown = "showAutoSaveCountdown"
    static let keywordValues = "keywordValues"
    static let primarySaveDirectory = "primarySaveDirectory"
    static let secondarySaveDirectory = "secondarySaveDirectory"
    static let launchAtLogin = "launchAtLogin"
  }

  @Published var fullScreenShortcut: ShortcutDefinition {
    didSet { save(fullScreenShortcut, forKey: Key.fullScreenShortcut) }
  }

  @Published var selectionShortcut: ShortcutDefinition {
    didSet { save(selectionShortcut, forKey: Key.selectionShortcut) }
  }

  @Published var chainedCaptureShortcut: ShortcutDefinition {
    didSet { save(chainedCaptureShortcut, forKey: Key.chainedCaptureShortcut) }
  }

  @Published var chainedTargetShortcut: ShortcutDefinition? {
    didSet {
      if let chainedTargetShortcut {
        save(chainedTargetShortcut, forKey: Key.chainedTargetShortcut)
      } else {
        defaults.removeObject(forKey: Key.chainedTargetShortcut)
        defaults.synchronize()
      }
    }
  }

  @Published var visualPromptEnabled: Bool {
    didSet { defaults.set(visualPromptEnabled, forKey: Key.visualPrompt) }
  }

  @Published var promptSize: PromptSize {
    didSet { save(promptSize, forKey: Key.promptSize) }
  }

  @Published var autoSaveDelay: Int {
    didSet { defaults.set(autoSaveDelay, forKey: Key.autoSaveDelay) }
  }

  @Published var showAutoSaveCountdown: Bool {
    didSet { defaults.set(showAutoSaveCountdown, forKey: Key.showAutoSaveCountdown) }
  }

  @Published var keywordValues: String {
    didSet { defaults.set(keywordValues, forKey: Key.keywordValues) }
  }

  @Published var primarySaveDirectory: URL {
    didSet { defaults.set(primarySaveDirectory.path, forKey: Key.primarySaveDirectory) }
  }

  @Published var secondarySaveDirectory: URL {
    didSet { defaults.set(secondarySaveDirectory.path, forKey: Key.secondarySaveDirectory) }
  }

  @Published var launchAtLogin: Bool {
    didSet {
      defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
      guard !isLoading else { return }
      do {
        if launchAtLogin {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
      } catch {
        launchAtLogin = SMAppService.mainApp.status == .enabled
      }
    }
  }

  private let defaults: UserDefaults
  private var isLoading = true

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    fullScreenShortcut =
      Self.load(
        ShortcutDefinition.self,
        forKey: Key.fullScreenShortcut,
        from: defaults
      ) ?? .fullScreen
    selectionShortcut =
      Self.load(
        ShortcutDefinition.self,
        forKey: Key.selectionShortcut,
        from: defaults
      ) ?? .selection
    chainedCaptureShortcut =
      Self.load(
        ShortcutDefinition.self,
        forKey: Key.chainedCaptureShortcut,
        from: defaults
      ) ?? .chainedSelection
    chainedTargetShortcut = Self.load(
      ShortcutDefinition.self,
      forKey: Key.chainedTargetShortcut,
      from: defaults
    )
    visualPromptEnabled = defaults.object(forKey: Key.visualPrompt) as? Bool ?? true
    promptSize =
      Self.load(PromptSize.self, forKey: Key.promptSize, from: defaults) ?? .small
    let storedAutoSaveDelay = defaults.object(forKey: Key.autoSaveDelay) as? Int ?? 5
    autoSaveDelay = [3, 5, 7, 10].contains(storedAutoSaveDelay) ? storedAutoSaveDelay : 5
    showAutoSaveCountdown =
      defaults.object(forKey: Key.showAutoSaveCountdown) as? Bool ?? true
    keywordValues =
      defaults.object(forKey: Key.keywordValues) == nil
      ? "bug"
      : defaults.string(forKey: Key.keywordValues) ?? ""
    let desktop =
      FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    primarySaveDirectory = Self.loadDirectory(
      forKey: Key.primarySaveDirectory,
      from: defaults,
      fallback: desktop
    )
    secondarySaveDirectory = Self.loadDirectory(
      forKey: Key.secondarySaveDirectory,
      from: defaults,
      fallback: desktop
    )
    launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
    isLoading = false
  }

  private func save<T: Encodable>(_ value: T, forKey key: String) {
    if let data = try? JSONEncoder().encode(value) {
      defaults.set(data, forKey: key)
      defaults.synchronize()
    }
  }

  private static func load<T: Decodable>(
    _ type: T.Type,
    forKey key: String,
    from defaults: UserDefaults
  ) -> T? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private static func loadDirectory(
    forKey key: String,
    from defaults: UserDefaults,
    fallback: URL
  ) -> URL {
    guard let path = defaults.string(forKey: key), !path.isEmpty else { return fallback }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return fallback }
    return URL(fileURLWithPath: path, isDirectory: true)
  }
}
