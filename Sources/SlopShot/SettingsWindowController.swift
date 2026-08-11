import AppKit
import SlopShotCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
  init(preferences: Preferences, onShortcutChange: @escaping () -> Void) {
    let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
    let contentSize = NSSize(
      width: 480,
      height: min(920, max(620, visibleHeight - 48))
    )
    let view = SettingsView(
      preferences: preferences,
      onShortcutChange: onShortcutChange,
      contentSize: contentSize
    )
    let host = NSHostingController(rootView: view)
    let window = NSWindow(contentViewController: host)
    window.title = "SlopShot"
    window.styleMask = [.titled, .closable]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.backgroundColor = .windowBackgroundColor
    window.setContentSize(contentSize)
    window.center()
    super.init(window: window)
    shouldCascadeWindows = false
  }

  required init?(coder: NSCoder) { nil }

  func show() {
    showWindow(nil)
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    window?.makeFirstResponder(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

private struct SettingsView: View {
  @ObservedObject var preferences: Preferences
  let onShortcutChange: () -> Void
  let contentSize: NSSize

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 0) {
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

      settingRow("Show countdown") {
        Toggle("", isOn: $preferences.showAutoSaveCountdown)
          .labelsHidden()
          .toggleStyle(.switch)
          .frame(width: 104, alignment: .trailing)
          .help("Auto-save still runs when hidden")
      }
      .padding(.top, 18)

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

        Text("Keyword detection")
          .font(.system(size: 13, weight: .semibold))

        settingRow("Keywords") {
          TextField("bug, feature", text: $preferences.keywordValues)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .padding(.vertical, 5)
            .overlay(alignment: .bottom) { Divider() }
            .frame(width: 220)
            .help("Comma-separated · clear to disable")
        }
        .padding(.top, 16)

        HStack(spacing: 6) {
          Image(systemName: "info.circle")
          Text("Comma-separated · clear to disable")
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
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollIndicators(.visible)
    .frame(width: contentSize.width, height: contentSize.height)
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
