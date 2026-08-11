import CoreGraphics
import Foundation
import ImageIO
import SlopShotCore
import UniformTypeIdentifiers

enum VerificationError: Error, CustomStringConvertible {
  case failed(String)

  var description: String {
    switch self {
    case .failed(let message): message
    }
  }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() { throw VerificationError.failed(message) }
}

func unwrap<T>(_ value: T?, _ message: String) throws -> T {
  guard let value else { throw VerificationError.failed(message) }
  return value
}

func makePNG(at url: URL, width: Int, height: Int) throws {
  let colorSpace = try unwrap(CGColorSpace(name: CGColorSpace.sRGB), "sRGB is unavailable")
  let context = try unwrap(
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), "Cannot create test image")
  context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let image = try unwrap(context.makeImage(), "Cannot render test image")
  let destination = try unwrap(
    CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    ), "Cannot create test PNG")
  CGImageDestinationAddImage(destination, image, nil)
  try require(CGImageDestinationFinalize(destination), "Cannot write test PNG")
}

func runCommand(_ executable: String, arguments: [String]) throws {
  let process = Process()
  let errors = Pipe()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.standardOutput = FileHandle.nullDevice
  process.standardError = errors
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    let detail = String(
      decoding: errors.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    throw VerificationError.failed(detail.isEmpty ? "Command failed: \(executable)" : detail)
  }
}

func verifyVersions() throws {
  try require(
    SemanticVersion("v1.10.0")! > SemanticVersion("1.9.9")!, "Semantic version ordering failed")
  try require(
    SemanticVersion("1.0")! == SemanticVersion("1.0.0")!, "Semantic version normalization failed")
}

func verifyFilenames() throws {
  let date = Date(timeIntervalSince1970: 1_723_392_000)
  let first = FilenameGenerator.baseName(for: date) + ".png"
  let result = FilenameGenerator.availableURL(
    in: URL(fileURLWithPath: "/tmp"),
    date: date,
    reservedNames: [first],
    fileExists: { _ in false }
  )
  try require(result.lastPathComponent.hasSuffix(" (2).png"), "Filename collision handling failed")
}

func verifyReleaseSignatures() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("SlopShot-signature-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let keyURL = root.appendingPathComponent("release-key")
  try runCommand(
    "/usr/bin/ssh-keygen",
    arguments: ["-q", "-t", "ed25519", "-N", "", "-C", "test", "-f", keyURL.path]
  )
  let publicKey = try String(
    contentsOf: keyURL.appendingPathExtension("pub"),
    encoding: .utf8
  )
  let manifestURL = root.appendingPathComponent("SlopShot-arm64.zip.sha256")
  let signatureURL = manifestURL.appendingPathExtension("sig")
  let manifest = "\(String(repeating: "a", count: 64))  SlopShot-arm64.zip\n"
  try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
  try runCommand(
    "/usr/bin/ssh-keygen",
    arguments: [
      "-Y", "sign", "-f", keyURL.path, "-n", ReleaseVerifier.namespace, manifestURL.path,
    ]
  )

  try ReleaseVerifier.verifySignature(
    manifestURL: manifestURL,
    signatureURL: signatureURL,
    publicKey: publicKey
  )
  let expectedHash = try ReleaseVerifier.expectedSHA256(
    in: Data(manifest.utf8),
    archiveName: "SlopShot-arm64.zip"
  )
  try require(expectedHash == String(repeating: "a", count: 64), "Checksum parsing failed")

  try "\(String(repeating: "b", count: 64))  SlopShot-arm64.zip\n".write(
    to: manifestURL,
    atomically: true,
    encoding: .utf8
  )
  var rejectedTampering = false
  do {
    try ReleaseVerifier.verifySignature(
      manifestURL: manifestURL,
      signatureURL: signatureURL,
      publicKey: publicKey
    )
  } catch {
    rejectedTampering = true
  }
  try require(rejectedTampering, "A tampered checksum manifest passed signature verification")

  var rejectedWrongFilename = false
  do {
    _ = try ReleaseVerifier.expectedSHA256(
      in: Data("\(String(repeating: "a", count: 64))  Other.zip\n".utf8),
      archiveName: "SlopShot-arm64.zip"
    )
  } catch {
    rejectedWrongFilename = true
  }
  try require(rejectedWrongFilename, "A checksum for the wrong archive was accepted")
}

func verifyAnnotation() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("SlopShot-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source.png")
  let output = root.appendingPathComponent("output.png")
  let largeOutput = root.appendingPathComponent("output-large.png")
  try makePNG(at: source, width: 120, height: 60)
  let originalData = try Data(contentsOf: source)
  let expected = SlopShotMetadata(
    captureId: UUID(),
    prompt: "Button overlaps footer.\nKeep Unicode: नमस्ते",
    capturedAt: Date(timeIntervalSince1970: 1_723_392_000.125_789),
    displayIndex: 1,
    displayCount: 2,
    visualPromptEmbedded: true
  )
  try ImageAnnotator.annotate(sourceURL: source, destinationURL: output, metadata: expected)

  try require(ImageAnnotator.metadata(at: output) == expected, "Metadata round-trip failed")
  let sourceAfterAnnotation = try Data(contentsOf: source)
  try require(sourceAfterAnnotation == originalData, "Original capture was modified")
  let imageSource = try unwrap(
    CGImageSourceCreateWithURL(output as CFURL, nil), "Cannot read output PNG")
  let image = try unwrap(
    CGImageSourceCreateImageAtIndex(imageSource, 0, nil), "Cannot decode output PNG")
  try require(image.width == 120 && image.height > 60, "Footer dimensions are invalid")
  try ImageAnnotator.annotate(
    sourceURL: source,
    destinationURL: largeOutput,
    metadata: expected,
    promptSize: .large
  )
  let largeImageSource = try unwrap(
    CGImageSourceCreateWithURL(largeOutput as CFURL, nil), "Cannot read large prompt PNG")
  let largeImage = try unwrap(
    CGImageSourceCreateImageAtIndex(largeImageSource, 0, nil),
    "Cannot decode large prompt PNG"
  )
  try require(largeImage.height > image.height, "Prompt size selection did not change the footer")
  let properties = try unwrap(
    CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
    "Cannot read output properties"
  )
  let png = try unwrap(
    properties[kCGImagePropertyPNGDictionary] as? [CFString: Any], "PNG properties are missing")
  try require(
    png[kCGImagePropertyPNGDescription] as? String == expected.prompt, "PNG Description is missing")
}

do {
  try verifyVersions()
  try verifyFilenames()
  try verifyReleaseSignatures()
  try verifyAnnotation()
  print("SlopShotCore verification passed")
} catch {
  FileHandle.standardError.write(Data("SlopShotCore verification failed: \(error)\n".utf8))
  exit(1)
}
