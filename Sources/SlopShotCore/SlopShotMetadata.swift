import Foundation

public struct SlopShotMetadata: Codable, Equatable, Sendable {
  public static let schemaVersion = "1"

  public let captureId: UUID
  public let prompt: String
  public let capturedAt: Date
  public let displayIndex: Int
  public let displayCount: Int
  public let visualPromptEmbedded: Bool
  public let keywords: [String]

  public init(
    captureId: UUID,
    prompt: String,
    capturedAt: Date,
    displayIndex: Int,
    displayCount: Int,
    visualPromptEmbedded: Bool,
    keywords: [String] = []
  ) {
    self.captureId = captureId
    self.prompt = prompt
    let milliseconds = floor(capturedAt.timeIntervalSince1970 * 1_000) / 1_000
    self.capturedAt = Date(timeIntervalSince1970: milliseconds)
    self.displayIndex = displayIndex
    self.displayCount = displayCount
    self.visualPromptEmbedded = visualPromptEmbedded
    self.keywords = keywords
  }
}
