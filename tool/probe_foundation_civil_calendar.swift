import Foundation

// Run with `swift tool/probe_foundation_civil_calendar.swift`.
// This observes Foundation conversion; it is not a date-picker acceptance test.
for identifier in [Calendar.Identifier.gregorian, .iso8601] {
  var calendar = Calendar(identifier: identifier)
  calendar.timeZone = .gmt
  for (year, month, day) in [(1500, 2, 29), (1582, 10, 10), (2000, 2, 29)] {
    let proposed = DateComponents(year: year, month: month, day: day, hour: 12)
    guard let date = calendar.date(from: proposed) else {
      print(identifier, "rejected", year, month, day)
      continue
    }
    let actual = calendar.dateComponents([.year, .month, .day], from: date)
    print(identifier, "input:", year, month, day, "output:", actual)
  }
}
