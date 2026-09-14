import Foundation

struct CivilDateDomain: Equatable, Sendable {
  let first: CivilDate
  let last: CivilDate
  let allowed: [CivilDate]
  let years: [Int]
  private let choices: [Int: [Int: [Int]]]
  init(first: CivilDate, last: CivilDate, allowed: [CivilDate] = []) throws {
    guard allowed.count <= Int(UInt16.max) else { throw WireError.limitExceeded }
    guard first.isValid, last.isValid, first <= last,
      allowed.allSatisfy({ $0.isValid && $0 >= first && $0 <= last }),
      zip(allowed, allowed.dropFirst()).allSatisfy({ $0 < $1 })
    else { throw TreeError.invalidProperties }
    self.first = first
    self.last = last
    self.allowed = allowed
    var choices: [Int: [Int: [Int]]] = [:]
    for date in allowed {
      choices[date.year, default: [:]][date.month, default: []].append(date.day)
    }
    self.choices = choices
    years = allowed.isEmpty ? Array(first.year...last.year) : choices.keys.sorted()
  }
  func months(in year: Int) -> [Int] {
    guard (first.year...last.year).contains(year) else { return [] }
    if !allowed.isEmpty { return choices[year]?.keys.sorted() ?? [] }
    return Array((year == first.year ? first.month : 1)...(year == last.year ? last.month : 12))
  }
  func days(in year: Int, month: Int) -> [Int] {
    guard months(in: year).contains(month) else { return [] }
    if !allowed.isEmpty { return choices[year]?[month] ?? [] }
    let start = year == first.year && month == first.month ? first.day : 1
    let end =
      year == last.year && month == last.month
      ? last.day : CivilDate.daysInMonth(year: year, month: month)
    return Array(start...end)
  }
  func contains(_ value: CivilDate) -> Bool {
    guard value.isValid, value >= first, value <= last else { return false }
    return allowed.isEmpty || choices[value.year]?[value.month]?.contains(value.day) == true
  }
  func selectingYear(_ year: Int, from value: CivilDate) -> CivilDate? {
    guard value.isValid, let month = nearest(months(in: year), to: value.month),
      let day = nearest(days(in: year, month: month), to: value.day)
    else { return nil }
    return CivilDate(year: year, month: month, day: day)
  }
  func selectingMonth(_ month: Int, from value: CivilDate) -> CivilDate? {
    guard value.isValid, let day = nearest(days(in: value.year, month: month), to: value.day) else {
      return nil
    }
    return CivilDate(year: value.year, month: month, day: day)
  }
  func selectingDay(_ day: Int, from value: CivilDate) -> CivilDate? {
    guard value.isValid else { return nil }
    let proposed = CivilDate(year: value.year, month: value.month, day: day)
    return contains(proposed) ? proposed : nil
  }
  private func nearest(_ choices: [Int], to value: Int) -> Int? {
    choices.min { abs($0 - value) < abs($1 - value) }
  }
}
