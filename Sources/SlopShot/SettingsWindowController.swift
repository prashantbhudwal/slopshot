import AppKit
import SlopShotCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
  init(preferences: Preferences, onShortcutChange: @escaping () -> Void) {
    let view = SettingsView(preferences: preferences, onShortcutChange: onShortcutChange)
    let host = NSHostingController(rootView: view)
    let window = NSWindow(contentViewController: host)
    window.title = "SlopShot"
    window.styleMask = [.titled, .closable]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.backgroundColor = .windowBackgroundColor
    window.setContentSize(NSSize(width: 440, height: 700))
    window.center()
    super.init(window: window)
    shouldCascadeWindows = false
  }

  required init?(coder: NSCoder) { nil }

  func show() {
    showWindow(nil)
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

private struct SettingsView: View {
  @ObservedObject var preferences: Preferences
  let onShortcutChange: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Settings")
        .font(.system(size: 22, weight: .semibold))
        .padding(.bottom, 30)

      settingRow("All displays") {
        HStack(spacing: 12) {
          ShortcutRecorder(
            shortcut: $preferences.fullScreenShortcut,
            onChange: onShortcutChange
          )
          .id("full-screen-shortcut")
          .frame(width: 112, height: 28)
          .help("Capture every display")
          resetShortcutButton(disabled: preferences.fullScreenShortcut == .fullScreen) {
            preferences.fullScreenShortcut = .fullScreen
            onShortcutChange()
          }
        }
      }

      settingRow("Area or window") {
        HStack(spacing: 12) {
          ShortcutRecorder(
            shortcut: $preferences.selectionShortcut,
            onChange: onShortcutChange
          )
          .id("selection-shortcut")
          .frame(width: 112, height: 28)
          .help("Select an area; press Space for a window")
          resetShortcutButton(disabled: preferences.selectionShortcut == .selection) {
            preferences.selectionShortcut = .selection
            onShortcutChange()
          }
        }
      }
      .padding(.top, 18)

      Divider()
        .padding(.vertical, 22)

      Text("Chained shortcuts")
        .font(.system(size: 13, weight: .semibold))

      settingRow("Capture area") {
        HStack(spacing: 12) {
          ShortcutRecorder(
            shortcut: $preferences.chainedCaptureShortcut,
            onChange: onShortcutChange
          )
          .id("chained-capture-shortcut")
          .frame(width: 112, height: 28)
          .help("Capture, focus the prompt, then fire the chained shortcut")
          resetShortcutButton(
            disabled: preferences.chainedCaptureShortcut == .chainedSelection
          ) {
            preferences.chainedCaptureShortcut = .chainedSelection
            onShortcutChange()
          }
        }
      }
      .padding(.top, 16)

      settingRow("Then press") {
        HStack(spacing: 12) {
          OptionalShortcutRecorder(
            shortcut: $preferences.chainedTargetShortcut,
            onChange: {}
          )
          .id("chained-target-shortcut")
          .frame(width: 112, height: 28)
          .help("Delete clears the shortcut")
          resetShortcutButton(disabled: preferences.chainedTargetShortcut == nil) {
            preferences.chainedTargetShortcut = nil
          }
        }
      }
      .padding(.top, 18)

      HStack(spacing: 6) {
        Image(systemName: "info.circle")
        Text("Focuses prompt first · Accessibility required")
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .padding(.top, 8)

      Divider()
        .padding(.vertical, 22)

      settingRow("Auto-save delay") {
        Picker("", selection: $preferences.autoSaveDelay) {
          ForEach([3, 5, 7, 10], id: \.self) { seconds in
            Text("\(seconds) seconds").tag(seconds)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 104)
      }

      settingRow("↩ saves to") {
        locationButton(preferences.primarySaveDirectory) {
          chooseDirectory(current: preferences.primarySaveDirectory) {
            preferences.primarySaveDirectory = $0
          }
        }
      }
      .padding(.top, 18)

      settingRow("⌘↩ saves to") {
        locationButton(preferences.secondarySaveDirectory) {
          chooseDirectory(current: preferences.secondarySaveDirectory) {
            preferences.secondarySaveDirectory = $0
          }
        }
      }
      .padding(.top, 18)

      Divider()
        .padding(.vertical, 22)

      settingRow("Show prompt in image") {
        Toggle("", isOn: $preferences.visualPromptEnabled)
          .labelsHidden()
          .toggleStyle(.switch)
          .frame(width: 104, alignment: .trailing)
          .help(promptStorageDescription)
      }

      HStack(spacing: 6) {
        Image(systemName: "info.circle")
        Text(promptStorageDescription)
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .padding(.top, 8)

      settingRow("Prompt size") {
        Picker("", selection: $preferences.promptSize) {
          ForEach(PromptSize.allCases, id: \.self) { size in
            Text(size.title).tag(size)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 104)
      }
      .disabled(!preferences.visualPromptEnabled)
      .padding(.top, 18)

      HStack(spacing: 6) {
        Image(systemName: "info.circle")
        Text("Text size in saved image")
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .padding(.top, 8)

      Divider()
        .padding(.vertical, 22)

      settingRow("Open at login") {
        Toggle("", isOn: $preferences.launchAtLogin)
          .labelsHidden()
          .toggleStyle(.switch)
          .frame(width: 104, alignment: .trailing)
      }

      Spacer(minLength: 0)
    }
    .padding(32)
    .frame(width: 440, height: 700)
  }

  private var promptStorageDescription: String {
    preferences.visualPromptEnabled ? "Metadata and image pixels" : "Metadata only"
  }

  private func resetShortcutButton(
    disabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: "arrow.counterclockwise")
        .font(.system(size: 11, weight: .medium))
        .frame(width: 16, height: 20)
    }
    .buttonStyle(.borderless)
    .disabled(disabled)
    .help("Reset shortcut")
  }

  private func locationButton(_ url: URL, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Text(url.lastPathComponent)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .semibold))
      }
      .frame(width: 104, alignment: .trailing)
    }
    .buttonStyle(.borderless)
    .help(url.path)
  }

  private func chooseDirectory(current: URL, completion: (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = current
    panel.prompt = "Choose"
    if panel.runModal() == .OK, let url = panel.url {
      completion(url)
    }
  }

  private func settingRow<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(spacing: 24) {
      Text(title)
      Spacer(minLength: 24)
      content()
    }
  }
}
