import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable {
  public let components: [Int]

  public init?(_ rawValue: String) {
    let normalized =
      rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingPrefix("v")
      .split(separator: "-", maxSplits: 1)
      .first ?? ""
    let parsed = normalized.split(separator: ".").map(String.init).map(Int.init)
    guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else { return nil }
    var components = parsed.compactMap { $0 }
    while components.count > 1, components.last == 0 { components.removeLast() }
    self.components = components
  }

  public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    let count = max(lhs.components.count, rhs.components.count)
    for index in 0..<count {
      let left = index < lhs.components.count ? lhs.components[index] : 0
      let right = index < rhs.components.count ? rhs.components[index] : 0
      if left != right { return left < right }
    }
    return false
  }
}

extension String {
  fileprivate func trimmingPrefix(_ prefix: Character) -> Substring {
    hasPrefix(String(prefix)) ? dropFirst() : self[...]
  }
}
