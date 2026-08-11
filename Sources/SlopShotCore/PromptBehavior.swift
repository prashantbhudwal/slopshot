import CoreGraphics
import Foundation

public enum PromptPointerTarget: Sendable {
  case image
  case composer
}

public struct PromptAutoSaveState: Sendable {
  public private(set) var isArmed = true

  public init() {}

  public mutating func registerPointerDown(on target: PromptPointerTarget) {
    if target == .composer { isArmed = false }
  }

  public var composerPlaceholder: String { "Add context…" }

  public func countdownText(seconds: Int, showsCountdown: Bool) -> String? {
    showsCountdown ? "Saving in \(seconds)s" : nil
  }
}

public enum PromptInteractionPolicy {
  public static func shouldPauseForResponderActivation(
    isLeftMouseDown: Bool,
    isInsideComposer: Bool
  ) -> Bool {
    isLeftMouseDown && isInsideComposer
  }
}

public struct PromptKeywordSelectionState: Sendable {
  public let commaSeparatedValues: String
  private var suppressed = Set<String>()

  public init(commaSeparatedValues: String) {
    self.commaSeparatedValues = commaSeparatedValues
  }

  public mutating func suppress(_ keyword: String) {
    suppressed.insert(keyword)
  }

  public func detectedKeywords(in prompt: String) -> [String] {
    KeywordDetector.detectedKeywords(
      in: prompt,
      commaSeparatedValues: commaSeparatedValues
    ).filter { !suppressed.contains($0) }
  }
}

public enum PromptLayoutMetrics {
  public static let imageToChipSpacing: CGFloat = 10
  public static let keywordStripHeight: CGFloat = 22
  public static let keywordStripToComposerSpacing: CGFloat = 8

  public static func panelHeight(
    previewHeight: CGFloat,
    inputHeight: CGFloat,
    detectedKeywordCount: Int
  ) -> CGFloat {
    _ = detectedKeywordCount
    return previewHeight + imageToChipSpacing + keywordStripHeight
      + keywordStripToComposerSpacing + inputHeight
  }
}
