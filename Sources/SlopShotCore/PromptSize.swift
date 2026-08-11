import Foundation

public enum PromptSize: String, Codable, CaseIterable, Sendable {
  case small
  case medium
  case large

  public var title: String { rawValue.capitalized }

  func fontSize(for imageWidth: Int) -> CGFloat {
    let width = CGFloat(imageWidth)
    switch self {
    case .small:
      return max(13, min(18, width * 0.014))
    case .medium:
      return max(15, min(22, width * 0.016))
    case .large:
      return max(17, min(28, width * 0.020))
    }
  }
}
