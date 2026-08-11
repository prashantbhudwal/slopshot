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

func containsRedPixel(in image: CGImage) -> Bool {
  let width = image.width
  let height = image.height
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
  let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
    guard
      let context = CGContext(
        data: bytes.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
  }
  guard rendered else { return false }
  return stride(from: 0, to: pixels.count, by: 4).contains { offset in
    pixels[offset] > 180 && pixels[offset + 1] < 140 && pixels[offset + 2] < 140
  }
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

func verifyKeywordDetection() throws {
  let configured = KeywordDetector.configuredKeywords(
    from: " bug, Feature Request, #BUG, accessibility "
  )
  try require(
    configured == ["bug", "feature request", "accessibility"],
    "Keyword parsing or deduplication failed"
  )
  try require(
    KeywordDetector.detectedKeywords(
      in: "This BUG needs a feature   request, not a debugger change.",
      commaSeparatedValues: "bug, feature request, debug"
    ) == ["bug", "feature request"],
    "Whole-word keyword detection failed"
  )
  try require(
    KeywordDetector.detectedKeywords(in: "debugger", commaSeparatedValues: "bug").isEmpty,
    "A partial word triggered keyword detection"
  )
  try require(
    KeywordDetector.detectedKeywords(in: "bug", commaSeparatedValues: "").isEmpty,
    "An empty keyword setting did not disable detection"
  )
  try require(
    KeywordDetector.hashtag(for: "feature request") == "#feature-request",
    "Multiword hashtag formatting failed"
  )
}

func verifyPromptBehavior() throws {
  var autoSave = PromptAutoSaveState()
  autoSave.registerPointerDown(on: .image)
  try require(autoSave.isArmed, "An image press disabled auto-save")
  try require(
    autoSave.composerPlaceholder == "Add context…",
    "Composer affordance is missing"
  )
  try require(
    autoSave.countdownText(seconds: 5, showsCountdown: true) == "Saving in 5s",
    "Visible countdown text is incorrect"
  )
  try require(
    autoSave.countdownText(seconds: 5, showsCountdown: false) == nil,
    "Hidden countdown still produced UI text"
  )
  try require(autoSave.isArmed, "Hiding countdown text disabled auto-save")
  autoSave.registerPointerDown(on: .composer)
  try require(!autoSave.isArmed, "A composer press did not disable auto-save")

  try require(
    PromptInteractionPolicy.shouldPauseForResponderActivation(
      isLeftMouseDown: true,
      isInsideComposer: true
    ),
    "A real composer click was not recognized"
  )
  try require(
    !PromptInteractionPolicy.shouldPauseForResponderActivation(
      isLeftMouseDown: true,
      isInsideComposer: false
    ),
    "An image click was treated as composer interaction"
  )

  let noTagsHeight = PromptLayoutMetrics.panelHeight(
    previewHeight: 180,
    inputHeight: 58,
    detectedKeywordCount: 0
  )
  let tagsHeight = PromptLayoutMetrics.panelHeight(
    previewHeight: 180,
    inputHeight: 58,
    detectedKeywordCount: 4
  )
  try require(noTagsHeight == tagsHeight, "Keyword chips caused a layout shift")

  var keywords = PromptKeywordSelectionState(commaSeparatedValues: "bug, feature")
  try require(
    keywords.detectedKeywords(in: "Bug in this feature") == ["bug", "feature"],
    "Live keyword state did not detect configured values"
  )
  keywords.suppress("bug")
  try require(
    keywords.detectedKeywords(in: "Bug in this feature") == ["feature"],
    "A removed keyword chip was added back"
  )
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
    visualPromptEmbedded: true,
    keywords: ["bug", "accessibility"]
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
  try require(containsRedPixel(in: image), "Detected keyword tag was not rendered in red")
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
  try verifyKeywordDetection()
  try verifyPromptBehavior()
  try verifyReleaseSignatures()
  try verifyAnnotation()
  print("SlopShotCore verification passed")
} catch {
  FileHandle.standardError.write(Data("SlopShotCore verification failed: \(error)\n".utf8))
  exit(1)
}
