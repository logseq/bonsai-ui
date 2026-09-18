import Foundation

struct CivilDateDomain: Equatable, Sendable {
  let first: CivilDate
  let last: CivilDate
  init(first: CivilDate, last: CivilDate) throws {
    guard first.isValid, last.isValid, first >= CivilDate.pickerMinimum, first <= last else {
      throw TreeError.invalidProperties
    }
    self.first = first
    self.last = last
  }
  func contains(_ value: CivilDate) -> Bool {
    value.isValid && value >= first && value <= last
  }
  var pickerRange: ClosedRange<Date> { try! first.dateForPicker()...last.dateForPicker() }
}

extension CivilDate {
  // Foundation's Gregorian calendar has a historical cutover. The system picker
  // contract starts at the first continuous Gregorian day instead of normalizing
  // earlier civil dates into different dates.
  static let pickerMinimum = CivilDate(year: 1582, month: 10, day: 15)
  static var pickerCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }
  func dateForPicker() throws -> Date {
    guard isValid, self >= Self.pickerMinimum,
      let date = Self.pickerCalendar.date(
        from: DateComponents(
          year: year, month: month, day: day, hour: 12)),
      try Self.fromPickerDate(date) == self
    else { throw TreeError.invalidProperties }
    return date
  }
  static func fromPickerDate(_ date: Date) throws -> Self {
    guard date.timeIntervalSinceReferenceDate.isFinite else { throw TreeError.invalidProperties }
    let components = pickerCalendar.dateComponents([.era, .year, .month, .day], from: date)
    guard components.era == 1, let year = components.year,
      let month = components.month, let day = components.day
    else { throw TreeError.invalidProperties }
    let value = Self(year: year, month: month, day: day)
    guard value.isValid, value >= pickerMinimum else { throw TreeError.invalidProperties }
    return value
  }
}
