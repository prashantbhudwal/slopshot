import Foundation

public enum FilenameGenerator {
  public static func baseName(
    for date: Date,
    prefix: String = "Screenshot",
    calendar: Calendar = .current
  ) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "\(prefix) \(formatter.string(from: date))"
  }

  public static func availableURL(
    in directory: URL,
    date: Date,
    prefix: String = "Screenshot",
    reservedNames: Set<String> = [],
    fileExists: (String) -> Bool
  ) -> URL {
    let base = baseName(for: date, prefix: prefix)
    var counter = 1

    while true {
      let suffix = counter == 1 ? "" : " (\(counter))"
      let name = "\(base)\(suffix).png"
      if !reservedNames.contains(name), !fileExists(name) {
        return directory.appendingPathComponent(name)
      }
      counter += 1
    }
  }
}
