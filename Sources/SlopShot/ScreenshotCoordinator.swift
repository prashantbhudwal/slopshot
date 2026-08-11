import AppKit
import CoreGraphics
import Foundation
import SlopShotCore

@MainActor
final class ScreenshotCoordinator {
  enum Mode: Sendable {
    case fullScreen
    case selection
  }

  private struct CaptureGroup: Sendable {
    let id: UUID
    let capturedAt: Date
    let directory: URL
    let imageURLs: [URL]
    let screen: NSScreenReference
    let chainedShortcut: ShortcutDefinition?
  }

  private struct NSScreenReference: @unchecked Sendable {
    let screen: NSScreen
  }

  private struct FinalizeResult: Sendable {
    let savedURLs: [URL]
    let clipboardPayloads: [ClipboardPayload]
    let failures: [String]
  }

  private struct ClipboardPayload: Sendable {
    let url: URL
    let pngData: Data?
  }

  private let preferences: Preferences
  private let promptDismissalDelayOverride: TimeInterval?
  private var panels: [UUID: PromptPanelController] = [:]
  private var panelOrder: [UUID] = []
  private var permissionWasRequested = false
  private var clipboardProviders: [ClipboardPNGDataProvider] = []

  init(preferences: Preferences, promptDismissalDelayOverride: TimeInterval? = nil) {
    self.preferences = preferences
    self.promptDismissalDelayOverride = promptDismissalDelayOverride
  }

  #if DEBUG
    func captureExisting(_ sourceURL: URL) {
      let id = UUID()
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SlopShot", isDirectory: true)
        .appendingPathComponent(id.uuidString, isDirectory: true)
      let temporaryURL = directory.appendingPathComponent("capture-1.png")
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
      } catch {
        try? FileManager.default.removeItem(at: directory)
        showError("The test screenshot could not be opened.", detail: error.localizedDescription)
        return
      }

      let screen = NSScreen.main ?? NSScreen.screens[0]
      let group = CaptureGroup(
        id: id,
        capturedAt: Date(),
        directory: directory,
        imageURLs: [temporaryURL],
        screen: NSScreenReference(screen: screen),
        chainedShortcut: nil
      )
      captureFinished(group: group, status: 0)
    }
  #endif

  func capture(_ mode: Mode, chainedShortcut: ShortcutDefinition? = nil) {
    guard ensureCapturePermission() else { return }

    let id = UUID()
    let capturedAt = Date()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SlopShot", isDirectory: true)
      .appendingPathComponent(id.uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      showError(
        "SlopShot could not create a temporary capture folder.", detail: error.localizedDescription
      )
      return
    }

    let displayCount = mode == .fullScreen ? max(1, NSScreen.screens.count) : 1
    let urls = (1...displayCount).map {
      directory.appendingPathComponent("capture-\($0).png")
    }
    let screen =
      NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
      ?? NSScreen.screens[0]
    let group = CaptureGroup(
      id: id,
      capturedAt: capturedAt,
      directory: directory,
      imageURLs: urls,
      screen: NSScreenReference(screen: screen),
      chainedShortcut: chainedShortcut
    )
    let arguments: [String]
    switch mode {
    case .fullScreen:
      arguments = ["-tpng"] + urls.map(\.path)
    case .selection:
      arguments = ["-i", "-Jselection", "-tpng", urls[0].path]
    }

    Task {
      let status = await ProcessRunner.run("/usr/sbin/screencapture", arguments: arguments)
      captureFinished(group: group, status: status)
    }
  }

  private func captureFinished(group: CaptureGroup, status: Int32) {
    let files = group.imageURLs.filter {
      guard FileManager.default.fileExists(atPath: $0.path) else { return false }
      return ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
    }
    guard status == 0, !files.isEmpty else {
      try? FileManager.default.removeItem(at: group.directory)
      if status != 0, status != 1 {
        showError(
          "The screenshot could not be captured.",
          detail: "screencapture exited with status \(status).")
      }
      return
    }

    let completedGroup = CaptureGroup(
      id: group.id,
      capturedAt: group.capturedAt,
      directory: group.directory,
      imageURLs: files,
      screen: group.screen,
      chainedShortcut: group.chainedShortcut
    )
    let primaryDirectory = preferences.primarySaveDirectory
    let secondaryDirectory = preferences.secondarySaveDirectory
    let locationsMatch =
      primaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
      == secondaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
    let primaryName = Self.locationName(primaryDirectory)
    let secondaryName = Self.locationName(secondaryDirectory)
    let savePlaceholder =
      locationsMatch
      ? "↩ Save to \(primaryName)"
      : "↩ \(primaryName) · ⌘↩ \(secondaryName)"
    let controller = PromptPanelController(
      id: group.id,
      imageURLs: files,
      savePlaceholder: savePlaceholder,
      dismissalDelay: promptDismissalDelayOverride ?? TimeInterval(preferences.autoSaveDelay),
      showsCountdown: preferences.showAutoSaveCountdown,
      keywordValues: preferences.keywordValues,
      dragFiles: { [weak self] in
        self?.saveForDrag(group: completedGroup, destinationDirectory: primaryDirectory) ?? []
      },
      onDragged: { [weak self] in self?.dismiss(group: completedGroup) },
      completion: { [weak self] prompt, keywords, slot, finished in
        let destination = slot == .primary ? primaryDirectory : secondaryDirectory
        self?.complete(
          group: completedGroup,
          prompt: prompt,
          keywords: keywords,
          destinationDirectory: destination,
          finished: finished
        )
      }
    )
    panels[group.id] = controller
    panelOrder.append(group.id)
    controller.show(on: group.screen.screen, stackIndex: panelOrder.count - 1)
    if let chainedShortcut = group.chainedShortcut {
      controller.focusComposer()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        ShortcutEmitter.post(chainedShortcut)
      }
    }
  }

  private func complete(
    group: CaptureGroup,
    prompt: String?,
    keywords: [String],
    destinationDirectory: URL,
    finished: @escaping () -> Void
  ) {
    let visualPrompt = preferences.visualPromptEnabled
    let promptSize = preferences.promptSize
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        Self.finalize(
          group: group,
          prompt: prompt,
          visualPrompt: visualPrompt,
          promptSize: promptSize,
          keywords: keywords,
          preloadClipboardData: true,
          destinationDirectory: destinationDirectory
        )
      }.value
      let clipboardUpdated = copyToClipboard(result.clipboardPayloads)
      finished()
      dismiss(group: group)
      if !clipboardUpdated, !result.savedURLs.isEmpty {
        showError(
          "The screenshot was saved, but could not be copied.",
          detail: "The finished file is available on your Desktop."
        )
      }
      reportFinalizeFailures(result.failures)
    }
  }

  private func dismiss(group: CaptureGroup) {
    panels[group.id] = nil
    panelOrder.removeAll { $0 == group.id }
    restackPanels(on: group.screen.screen)
  }

  private func saveForDrag(group: CaptureGroup, destinationDirectory: URL) -> [URL] {
    let result = Self.finalize(
      group: group,
      prompt: nil,
      visualPrompt: false,
      promptSize: .small,
      keywords: [],
      preloadClipboardData: false,
      destinationDirectory: destinationDirectory
    )
    copyToClipboard(result.clipboardPayloads)
    reportFinalizeFailures(result.failures)
    return result.savedURLs
  }

  @discardableResult
  private func copyToClipboard(_ payloads: [ClipboardPayload]) -> Bool {
    guard !payloads.isEmpty else { return false }
    let providers = payloads.map {
      ClipboardPNGDataProvider(url: $0.url, preloadedData: $0.pngData)
    }
    let items = zip(payloads, providers).map { payload, provider -> NSPasteboardItem in
      let item = NSPasteboardItem()
      item.setString(payload.url.absoluteString, forType: .fileURL)
      item.setDataProvider(provider, forTypes: [.png])
      return item
    }
    NSPasteboard.general.clearContents()
    let succeeded = NSPasteboard.general.writeObjects(items)
    clipboardProviders = succeeded ? providers : []
    return succeeded
  }

  private func reportFinalizeFailures(_ failures: [String]) {
    if !failures.isEmpty {
      showError(
        "The screenshot was saved, but SlopShot could not finish every file.",
        detail: failures.joined(separator: "\n")
      )
    }
  }

  nonisolated private static func finalize(
    group: CaptureGroup,
    prompt: String?,
    visualPrompt: Bool,
    promptSize: PromptSize,
    keywords: [String],
    preloadClipboardData: Bool,
    destinationDirectory: URL
  ) -> FinalizeResult {
    let manager = FileManager.default
    let desktop =
      manager.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    var reserved = Set<String>()
    var saved: [URL] = []
    var failures: [String] = []
    var isDirectory: ObjCBool = false
    let saveDirectory: URL
    if manager.fileExists(atPath: destinationDirectory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      saveDirectory = destinationDirectory
    } else {
      saveDirectory = desktop
      failures.append(
        "The selected save location was unavailable, so the capture was saved to Desktop.")
    }
    let screenshotPrefix = UserDefaults(suiteName: "com.apple.screencapture")?
      .string(forKey: "name")?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let filenamePrefix = screenshotPrefix.flatMap { $0.isEmpty ? nil : $0 } ?? "Screenshot"

    for (offset, sourceURL) in group.imageURLs.enumerated() {
      let destination = FilenameGenerator.availableURL(
        in: saveDirectory,
        date: group.capturedAt,
        prefix: filenamePrefix,
        reservedNames: reserved,
        fileExists: { manager.fileExists(atPath: saveDirectory.appendingPathComponent($0).path) }
      )
      reserved.insert(destination.lastPathComponent)

      if let prompt {
        let annotatedURL = group.directory.appendingPathComponent("annotated-\(offset + 1).png")
        let metadata = SlopShotMetadata(
          captureId: group.id,
          prompt: prompt,
          capturedAt: group.capturedAt,
          displayIndex: offset + 1,
          displayCount: group.imageURLs.count,
          visualPromptEmbedded: visualPrompt,
          keywords: keywords
        )
        do {
          try ImageAnnotator.annotate(
            sourceURL: sourceURL,
            destinationURL: annotatedURL,
            metadata: metadata,
            promptSize: promptSize
          )
          try manager.moveItem(at: annotatedURL, to: destination)
          saved.append(destination)
          try? manager.removeItem(at: sourceURL)
        } catch {
          failures.append("Display \(offset + 1): \(error.localizedDescription)")
          do {
            try manager.moveItem(at: sourceURL, to: destination)
            saved.append(destination)
          } catch {
            failures.append(
              "The original capture could not be saved: \(error.localizedDescription)")
          }
        }
      } else {
        do {
          try manager.moveItem(at: sourceURL, to: destination)
          saved.append(destination)
        } catch {
          failures.append(
            "The original capture could not be saved: \(error.localizedDescription)")
        }
      }
    }
    try? manager.removeItem(at: group.directory)
    let clipboardPayloads = saved.map {
      ClipboardPayload(
        url: $0,
        pngData: preloadClipboardData ? try? Data(contentsOf: $0) : nil
      )
    }
    return FinalizeResult(
      savedURLs: saved,
      clipboardPayloads: clipboardPayloads,
      failures: failures
    )
  }

  nonisolated private static func locationName(_ url: URL) -> String {
    let name = url.lastPathComponent
    return name.isEmpty ? url.path : name
  }

  private func restackPanels(on screen: NSScreen) {
    for (index, id) in panelOrder.enumerated() {
      panels[id]?.updateStackIndex(index, on: screen)
    }
  }

  private func ensureCapturePermission() -> Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    if !permissionWasRequested {
      permissionWasRequested = true
      if CGRequestScreenCaptureAccess() { return true }
      return false
    }
    let alert = NSAlert()
    alert.messageText = "Allow Screen Recording"
    alert.informativeText =
      "SlopShot needs Screen Recording access to capture screenshots. Enable SlopShot in System Settings > Privacy & Security > Screen Recording, then reopen the app."
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Not Now")
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn,
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    {
      NSWorkspace.shared.open(url)
    }
    return false
  }

  private func showError(_ message: String, detail: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = message
    alert.informativeText = detail
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
}

private final class ClipboardPNGDataProvider: NSObject, NSPasteboardItemDataProvider {
  private let url: URL
  private let preloadedData: Data?

  init(url: URL, preloadedData: Data?) {
    self.url = url
    self.preloadedData = preloadedData
  }

  func pasteboard(
    _ pasteboard: NSPasteboard?,
    item: NSPasteboardItem,
    provideDataForType type: NSPasteboard.PasteboardType
  ) {
    guard type == .png, let data = preloadedData ?? (try? Data(contentsOf: url)) else { return }
    item.setData(data, forType: .png)
  }
}

private enum ProcessRunner {
  static func run(_ executable: String, arguments: [String]) async -> Int32 {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.terminationHandler = { process in
        continuation.resume(returning: process.terminationStatus)
      }
      do {
        try process.run()
      } catch {
        continuation.resume(returning: -1)
      }
    }
  }
}
