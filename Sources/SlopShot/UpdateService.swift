import AppKit
import CryptoKit
import Foundation
import SlopShotCore

private struct GitHubRelease: Decodable, Sendable {
  struct Asset: Decodable, Sendable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
      case name
      case browserDownloadURL = "browser_download_url"
    }
  }

  let tagName: String
  let htmlURL: URL
  let assets: [Asset]

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case htmlURL = "html_url"
    case assets
  }
}

@MainActor
final class UpdateService {
  private let endpoint = URL(
    string: "https://api.github.com/repos/prashantbhudwal/slopshot/releases/latest")!

  func checkForUpdates() {
    Task {
      do {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SlopShot", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
          throw UpdateError.releaseUnavailable
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard
          let latest = SemanticVersion(release.tagName),
          let current = SemanticVersion(currentVersion)
        else { throw UpdateError.invalidVersion }

        if current < latest {
          offer(release: release, version: release.tagName)
        } else {
          show(message: "Up to date", detail: "SlopShot \(currentVersion)")
        }
      } catch {
        show(message: "Update unavailable", detail: error.localizedDescription, style: .warning)
      }
    }
  }

  private var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
  }

  private func offer(release: GitHubRelease, version: String) {
    let alert = NSAlert()
    alert.messageText = "SlopShot \(version) is available"
    alert.addButton(withTitle: "Install")
    alert.addButton(withTitle: "Later")
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
      install(release)
    }
  }

  private func install(_ release: GitHubRelease) {
    Task {
      do {
        let replacement = try await UpdateInstaller.stage(release: release)
        try UpdateInstaller.replaceOnQuit(with: replacement)
      } catch {
        show(message: "Update failed", detail: error.localizedDescription, style: .warning)
      }
    }
  }

  private func show(message: String, detail: String, style: NSAlert.Style = .informational) {
    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = message
    alert.informativeText = detail
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
}

private enum UpdateError: LocalizedError {
  case releaseUnavailable
  case invalidVersion
  case missingAsset
  case checksumMismatch
  case invalidBundle
  case invalidArchitecture
  case notInstalled
  case commandFailed(String)

  var errorDescription: String? {
    switch self {
    case .releaseUnavailable: "The latest release could not be loaded."
    case .invalidVersion: "The release version is invalid."
    case .missingAsset: "The arm64 release files are missing."
    case .checksumMismatch: "The downloaded archive failed verification."
    case .invalidBundle: "The downloaded app is invalid."
    case .invalidArchitecture: "The downloaded app is not built for Apple silicon."
    case .notInstalled: "Move SlopShot to ~/Applications before updating."
    case .commandFailed(let message): message
    }
  }
}

private enum UpdateInstaller {
  private static let archiveName = "SlopShot-arm64.zip"
  private static let checksumName = "SlopShot-arm64.zip.sha256"

  static func stage(release: GitHubRelease) async throws -> URL {
    guard
      let archiveAsset = release.assets.first(where: { $0.name == archiveName }),
      let checksumAsset = release.assets.first(where: { $0.name == checksumName })
    else { throw UpdateError.missingAsset }

    async let archiveRequest = URLSession.shared.data(from: archiveAsset.browserDownloadURL)
    async let checksumRequest = URLSession.shared.data(from: checksumAsset.browserDownloadURL)
    let ((archive, archiveResponse), (checksumData, checksumResponse)) = try await (
      archiveRequest, checksumRequest
    )
    guard
      (archiveResponse as? HTTPURLResponse)?.statusCode == 200,
      (checksumResponse as? HTTPURLResponse)?.statusCode == 200
    else { throw UpdateError.releaseUnavailable }

    let expected = String(decoding: checksumData, as: UTF8.self)
      .split(whereSeparator: { $0.isWhitespace })
      .first
      .map(String.init)?
      .lowercased()
    let actual = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
    guard expected == actual else { throw UpdateError.checksumMismatch }

    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("SlopShot-update-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let archiveURL = root.appendingPathComponent(archiveName)
    try archive.write(to: archiveURL, options: .atomic)
    try run("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, root.path])

    guard let appURL = findApp(in: root) else { throw UpdateError.invalidBundle }
    let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
    guard
      let info = NSDictionary(contentsOf: infoURL),
      info["CFBundleIdentifier"] as? String == "com.prashantbhudwal.slopshot",
      let executableName = info["CFBundleExecutable"] as? String
    else { throw UpdateError.invalidBundle }

    let executable = appURL.appendingPathComponent("Contents/MacOS/\(executableName)")
    do {
      try run("/usr/bin/lipo", arguments: [executable.path, "-verify_arch", "arm64"])
      try run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
    } catch {
      throw UpdateError.invalidArchitecture
    }
    return appURL
  }

  @MainActor
  static func replaceOnQuit(with replacement: URL) throws {
    let current = Bundle.main.bundleURL.standardizedFileURL
    let expectedParent = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Applications", isDirectory: true)
      .standardizedFileURL
    guard
      current.pathExtension == "app",
      current.lastPathComponent == "SlopShot.app",
      current.deletingLastPathComponent() == expectedParent
    else { throw UpdateError.notInstalled }

    let helperURL = replacement.deletingLastPathComponent().appendingPathComponent("update.sh")
    let script = """
      #!/bin/sh
      set -eu
      PID="$1"
      CURRENT="$2"
      REPLACEMENT="$3"
      BACKUP="${CURRENT%.app}.previous.app"
      while /bin/kill -0 "$PID" 2>/dev/null; do /bin/sleep 0.2; done
      if [ -e "$BACKUP" ]; then /bin/rm -rf -- "$BACKUP"; fi
      /bin/mv "$CURRENT" "$BACKUP"
      if /bin/mv "$REPLACEMENT" "$CURRENT" && /usr/bin/xattr -dr com.apple.quarantine "$CURRENT" && /usr/bin/open "$CURRENT"; then
        exit 0
      fi
      if [ -e "$CURRENT" ]; then /bin/rm -rf -- "$CURRENT"; fi
      /bin/mv "$BACKUP" "$CURRENT"
      /usr/bin/open "$CURRENT"
      exit 1
      """
    try script.write(to: helperURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)

    let helper = Process()
    helper.executableURL = URL(fileURLWithPath: "/bin/sh")
    helper.arguments = [
      helperURL.path, String(ProcessInfo.processInfo.processIdentifier), current.path,
      replacement.path,
    ]
    helper.standardOutput = FileHandle.nullDevice
    helper.standardError = FileHandle.nullDevice
    try helper.run()
    NSApp.terminate(nil)
  }

  private static func findApp(in directory: URL) -> URL? {
    let direct = directory.appendingPathComponent("SlopShot.app", isDirectory: true)
    if FileManager.default.fileExists(atPath: direct.path) { return direct }
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else { return nil }
    for case let url as URL in enumerator where url.lastPathComponent == "SlopShot.app" {
      return url
    }
    return nil
  }

  private static func run(_ executable: String, arguments: [String]) throws {
    let process = Process()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let data = errors.fileHandleForReading.readDataToEndOfFile()
      let message = String(decoding: data, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
      throw UpdateError.commandFailed(message.isEmpty ? "Update verification failed." : message)
    }
  }
}
