import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageAnnotationError: LocalizedError {
  case unreadableImage
  case cannotCreateContext
  case cannotCreateDestination
  case cannotWriteImage
  case cannotWriteMetadata(String)

  public var errorDescription: String? {
    switch self {
    case .unreadableImage: "The captured PNG could not be read."
    case .cannotCreateContext: "The annotation canvas could not be created."
    case .cannotCreateDestination: "The output PNG could not be created."
    case .cannotWriteImage: "The annotated PNG could not be written."
    case .cannotWriteMetadata(let detail): "SlopShot metadata could not be embedded (\(detail))."
    }
  }
}

public enum ImageAnnotator {
  public static let metadataNamespace = "https://slopshot.app/metadata/1.0/"
  public static let metadataPrefix = "slopshot"
  public static let metadataPointer =
    "Agent: Read the SlopShot prompt embedded in this image's metadata."

  public static func annotate(
    sourceURL: URL,
    destinationURL: URL,
    metadata: SlopShotMetadata,
    promptSize: PromptSize = .small
  ) throws {
    guard
      let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw ImageAnnotationError.unreadableImage
    }

    let footerText =
      metadata.visualPromptEmbedded
      ? "Prompt\n\(metadata.prompt)"
      : metadataPointer
    let composedImage = try compose(
      image: image,
      footerText: footerText,
      promptSize: promptSize
    )
    let xmp = try makeMetadata(metadata)

    guard
      let destination = CGImageDestinationCreateWithURL(
        destinationURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw ImageAnnotationError.cannotCreateDestination
    }

    var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    var png = (properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]) ?? [:]
    png[kCGImagePropertyPNGDescription] = metadata.prompt
    properties[kCGImagePropertyPNGDictionary] = png

    CGImageDestinationAddImageAndMetadata(
      destination,
      composedImage,
      xmp,
      properties as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
      throw ImageAnnotationError.cannotWriteImage
    }
    try verify(url: destinationURL, expected: metadata)
  }

  public static func metadata(at url: URL) -> SlopShotMetadata? {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let imageMetadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
    else { return nil }

    func value(_ field: String) -> String? {
      CGImageMetadataCopyStringValueWithPath(
        imageMetadata,
        nil,
        "\(metadataPrefix):\(field)" as CFString
      ) as String?
    }

    guard
      value("schemaVersion") == SlopShotMetadata.schemaVersion,
      let captureIdString = value("captureId"),
      let captureId = UUID(uuidString: captureIdString),
      let prompt = value("prompt"),
      let capturedAtString = value("capturedAt"),
      let capturedAt = ISO8601DateFormatter.slopShot.date(from: capturedAtString),
      let displayIndexString = value("displayIndex"),
      let displayIndex = Int(displayIndexString),
      let displayCountString = value("displayCount"),
      let displayCount = Int(displayCountString),
      let visualString = value("visualPromptEmbedded")
    else { return nil }

    return SlopShotMetadata(
      captureId: captureId,
      prompt: prompt,
      capturedAt: capturedAt,
      displayIndex: displayIndex,
      displayCount: displayCount,
      visualPromptEmbedded: visualString == "true"
    )
  }

  private static func compose(
    image: CGImage,
    footerText: String,
    promptSize: PromptSize
  ) throws -> CGImage {
    let width = image.width
    let fontSize = promptSize.fontSize(for: width)
    let padding = max(16, fontSize)
    let font = CTFontCreateWithName(".AppleSystemUIFont" as CFString, fontSize, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
        gray: 0.96, alpha: 1),
    ]
    let text = NSAttributedString(string: footerText, attributes: attributes)
    let framesetter = CTFramesetterCreateWithAttributedString(text)
    let constraint = CGSize(
      width: max(1, CGFloat(width) - (padding * 2)), height: .greatestFiniteMagnitude)
    let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
      framesetter, CFRange(), nil, constraint, nil)
    let separatorHeight = max(2, min(6, Int(ceil(CGFloat(width) * 0.003))))
    let contentHeight = Int(ceil(suggested.height + padding * 2))
    let footerHeight = contentHeight + separatorHeight
    let totalHeight = image.height + footerHeight

    guard
      let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: totalHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { throw ImageAnnotationError.cannotCreateContext }

    context.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: footerHeight))
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(
      CGRect(
        x: 0,
        y: footerHeight - separatorHeight,
        width: width,
        height: separatorHeight
      ))
    context.draw(image, in: CGRect(x: 0, y: footerHeight, width: width, height: image.height))

    let textRect = CGRect(
      x: padding,
      y: padding,
      width: CGFloat(width) - padding * 2,
      height: CGFloat(contentHeight) - padding * 2
    )
    let path = CGPath(rect: textRect, transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
    CTFrameDraw(frame, context)

    guard let result = context.makeImage() else {
      throw ImageAnnotationError.cannotCreateContext
    }
    return result
  }

  private static func makeMetadata(_ value: SlopShotMetadata) throws -> CGMutableImageMetadata {
    let metadata = CGImageMetadataCreateMutable()
    var error: Unmanaged<CFError>?
    guard
      CGImageMetadataRegisterNamespaceForPrefix(
        metadata,
        metadataNamespace as CFString,
        metadataPrefix as CFString,
        &error
      )
    else {
      throw error?.takeRetainedValue() ?? ImageAnnotationError.cannotWriteMetadata("namespace")
    }

    let values = [
      "schemaVersion": SlopShotMetadata.schemaVersion,
      "captureId": value.captureId.uuidString,
      "prompt": value.prompt,
      "capturedAt": ISO8601DateFormatter.slopShot.string(from: value.capturedAt),
      "displayIndex": String(value.displayIndex),
      "displayCount": String(value.displayCount),
      "visualPromptEmbedded": String(value.visualPromptEmbedded),
    ]
    for (key, item) in values {
      guard
        CGImageMetadataSetValueWithPath(
          metadata,
          nil,
          "\(metadataPrefix):\(key)" as CFString,
          item as CFString
        )
      else {
        throw ImageAnnotationError.cannotWriteMetadata(key)
      }
    }
    return metadata
  }

  private static func verify(url: URL, expected: SlopShotMetadata) throws {
    guard metadata(at: url) == expected else {
      try? FileManager.default.removeItem(at: url)
      throw ImageAnnotationError.cannotWriteMetadata("verification")
    }
  }
}

extension ISO8601DateFormatter {
  fileprivate static var slopShot: ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }
}
