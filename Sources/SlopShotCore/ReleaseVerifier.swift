import Foundation

public enum ReleaseVerificationError: LocalizedError {
  case invalidPublicKey
  case invalidManifest
  case invalidSignature(String)

  public var errorDescription: String? {
    switch self {
    case .invalidPublicKey:
      "The bundled SlopShot release-signing key is invalid."
    case .invalidManifest:
      "The signed release checksum manifest is invalid."
    case .invalidSignature(let detail):
      detail.isEmpty
        ? "The release signature is invalid."
        : "The release signature is invalid (\(detail))."
    }
  }
}

public enum ReleaseVerifier {
  public static let principal = "slopshot-release"
  public static let namespace = "slopshot-release"

  public static func expectedSHA256(
    in manifest: Data,
    archiveName: String
  ) throws -> String {
    guard let text = String(data: manifest, encoding: .utf8) else {
      throw ReleaseVerificationError.invalidManifest
    }
    let lines = text.split(whereSeparator: { $0.isNewline }).filter {
      !$0.trimmingCharacters(in: .whitespaces).isEmpty
    }
    guard lines.count == 1 else { throw ReleaseVerificationError.invalidManifest }

    let fields = lines[0].split(whereSeparator: { $0.isWhitespace })
    guard fields.count == 2,
      fields[1] == Substring(archiveName),
      fields[0].count == 64,
      fields[0].allSatisfy({ $0.isHexDigit })
    else {
      throw ReleaseVerificationError.invalidManifest
    }
    return fields[0].lowercased()
  }

  public static func verifySignature(
    manifestURL: URL,
    signatureURL: URL,
    publicKey: String
  ) throws {
    let keyFields = publicKey.split(whereSeparator: { $0.isWhitespace })
    guard keyFields.count >= 2,
      keyFields[0] == "ssh-ed25519",
      Data(base64Encoded: String(keyFields[1])) != nil
    else {
      throw ReleaseVerificationError.invalidPublicKey
    }

    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(
      "SlopShot-signature-verification-\(UUID().uuidString)",
      isDirectory: true
    )
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }

    let allowedSignersURL = directory.appendingPathComponent("allowed_signers")
    let allowedSigner = "\(principal) \(keyFields[0]) \(keyFields[1])\n"
    try allowedSigner.write(to: allowedSignersURL, atomically: true, encoding: .utf8)

    let input = try FileHandle(forReadingFrom: manifestURL)
    defer { try? input.close() }
    let errors = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
    process.arguments = [
      "-Y", "verify",
      "-f", allowedSignersURL.path,
      "-I", principal,
      "-n", namespace,
      "-s", signatureURL.path,
    ]
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      throw ReleaseVerificationError.invalidSignature(error.localizedDescription)
    }
    guard process.terminationStatus == 0 else {
      let detail = String(
        decoding: errors.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      throw ReleaseVerificationError.invalidSignature(detail)
    }
  }
}
