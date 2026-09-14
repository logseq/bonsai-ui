import Foundation

struct CivilDate: Equatable, Comparable, Sendable {
  // Keep proleptic Gregorian components independent of Foundation's historical cutover.
  let year: Int
  let month: Int
  let day: Int
  var isValid: Bool {
    guard (1...9999).contains(year), (1...12).contains(month) else { return false }
    return (1...Self.daysInMonth(year: year, month: month)).contains(day)
  }
  static func daysInMonth(year: Int, month: Int) -> Int {
    guard (1...9999).contains(year), (1...12).contains(month) else { return 0 }
    let leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
    return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
  }
  static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }
}

struct CivilTime: Equatable, Sendable {
  let hour: Int
  let minute: Int
  var isValid: Bool { (0..<24).contains(hour) && (0..<60).contains(minute) }
  func dateForPicker() throws -> Date {
    // Native picker views must use UTC. This Date carries clock fields, not an app timestamp.
    guard isValid else { throw TreeError.invalidProperties }
    return Date(timeIntervalSinceReferenceDate: Double((hour * 60 + minute) * 60))
  }
  static func fromPickerDate(_ date: Date) throws -> Self {
    let seconds = date.timeIntervalSinceReferenceDate
    guard seconds.isFinite else { throw TreeError.invalidProperties }
    let minute = Int(floor(seconds / 60).truncatingRemainder(dividingBy: 1440))
    let normalized = (minute + 1440) % 1440
    return Self(hour: normalized / 60, minute: normalized % 60)
  }
}

enum CivilTimeFormat: Int, Sendable {
  case system, hour12, hour24
  func applying(to locale: Locale) -> Locale {
    guard self != .system else { return locale }
    var components = Locale.Components(locale: locale)
    components.hourCycle = self == .hour12 ? .oneToTwelve : .zeroToTwentyThree
    return Locale(components: components)
  }
}
