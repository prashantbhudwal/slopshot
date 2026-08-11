import Foundation

public enum KeywordDetector {
  public static func configuredKeywords(from commaSeparatedValues: String) -> [String] {
    var seen = Set<String>()
    return commaSeparatedValues.split(separator: ",", omittingEmptySubsequences: false)
      .compactMap { value -> String? in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHash = trimmed.drop(while: { $0 == "#" })
        let normalized = withoutHash.split(whereSeparator: \Character.isWhitespace)
          .joined(separator: " ")
          .lowercased()
        guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
        return normalized
      }
  }

  public static func detectedKeywords(
    in prompt: String,
    commaSeparatedValues: String
  ) -> [String] {
    configuredKeywords(from: commaSeparatedValues).filter { keyword in
      let escaped = keyword.split(whereSeparator: \Character.isWhitespace)
        .map { NSRegularExpression.escapedPattern(for: String($0)) }
        .joined(separator: #"\s+"#)
      let pattern = "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
      guard
        let expression = try? NSRegularExpression(
          pattern: pattern,
          options: [.caseInsensitive]
        )
      else { return false }
      let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
      return expression.firstMatch(in: prompt, range: range) != nil
    }
  }

  public static func hashtag(for keyword: String) -> String {
    "#" + keyword.split(whereSeparator: \Character.isWhitespace).joined(separator: "-")
  }
}
