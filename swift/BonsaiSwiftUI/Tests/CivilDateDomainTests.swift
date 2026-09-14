import Testing

@testable import BonsaiSwiftUI

struct CivilDateDomainTests {
  private func date(_ year: Int, _ month: Int, _ day: Int) -> CivilDate {
    CivilDate(year: year, month: month, day: day)
  }

  @Test func rangeChoicesRespectPartialMonthsAndClampLeapDays() throws {
    let domain = try CivilDateDomain(first: date(2024, 2, 29), last: date(2025, 3, 10))
    #expect(domain.years == [2024, 2025])
    #expect(domain.months(in: 2024) == Array(2...12))
    #expect(domain.months(in: 2025) == [1, 2, 3])
    #expect(domain.months(in: 2023).isEmpty)
    #expect(domain.days(in: 2024, month: 2) == [29])
    #expect(domain.days(in: 2025, month: 3) == Array(1...10))
    #expect(domain.days(in: 2024, month: 1).isEmpty)
    #expect(domain.selectingYear(2025, from: date(2024, 2, 29)) == date(2025, 2, 28))
    #expect(domain.selectingYear(2024, from: date(2025, 1, 1)) == date(2024, 2, 29))
    #expect(domain.selectingMonth(3, from: date(2025, 2, 28)) == date(2025, 3, 10))
    #expect(domain.selectingMonth(1, from: date(2024, 2, 29)) == nil)
    #expect(domain.selectingDay(28, from: date(2024, 2, 29)) == nil)
    #expect(domain.selectingYear(2023, from: date(2024, 2, 29)) == nil)
  }

  @Test func restrictedChoicesNeverProposeUnavailableDatesAndPreferEarlierTies() throws {
    let allowed = [
      date(2024, 2, 29), date(2025, 6, 3), date(2026, 1, 2), date(2026, 1, 4), date(2026, 12, 31),
    ]
    let domain = try CivilDateDomain(
      first: date(2024, 1, 1), last: date(2026, 12, 31), allowed: allowed)
    #expect(domain.years == [2024, 2025, 2026])
    #expect(domain.months(in: 2026) == [1, 12])
    #expect(domain.days(in: 2026, month: 1) == [2, 4])
    #expect(domain.selectingYear(2026, from: date(2024, 2, 29)) == date(2026, 1, 4))
    #expect(domain.selectingYear(2026, from: date(2025, 6, 3)) == date(2026, 1, 2))
    #expect(domain.selectingMonth(12, from: date(2026, 1, 2)) == date(2026, 12, 31))
    #expect(domain.selectingYear(2024, from: date(2026, 12, 31)) == date(2024, 2, 29))
    #expect(domain.selectingDay(3, from: date(2026, 1, 2)) == nil)
    #expect(!domain.contains(date(2026, 1, 3)))
    #expect(allowed.allSatisfy(domain.contains))
    #expect(domain.selectingYear(Int.max, from: date(Int.min, 1, 1)) == nil)
    #expect(domain.selectingMonth(Int.min, from: date(2026, 1, 2)) == nil)
  }

  @Test func fullCivilRangeDoesNotLoseDatesAtTheHistoricalCalendarCutover() throws {
    let domain = try CivilDateDomain(first: date(1, 1, 1), last: date(9999, 12, 31))
    #expect(domain.years.count == 9999)
    #expect(domain.days(in: 1582, month: 10) == Array(1...31))
    #expect(domain.contains(date(1582, 10, 10)))
    #expect(!domain.contains(date(1500, 2, 29)))
    #expect(domain.selectingYear(1500, from: date(1600, 2, 29)) == date(1500, 2, 28))
    #expect(domain.selectingDay(31, from: date(9999, 12, 1)) == date(9999, 12, 31))
  }

  @Test func invalidBoundsAndNoncanonicalAllowedDatesAreRejected() throws {
    for (first, last) in [
      (date(2026, 2, 30), date(2026, 12, 31)), (date(2026, 1, 1), date(2025, 1, 1)),
    ] {
      #expect(throws: (any Error).self) { _ = try CivilDateDomain(first: first, last: last) }
    }
    let a = date(2026, 1, 1)
    let b = date(2026, 1, 2)
    for allowed in [
      [b, a], [a, a], [date(2026, 2, 30)], [date(2025, 12, 31)], [date(2027, 1, 1)],
    ] {
      #expect(throws: (any Error).self) {
        _ = try CivilDateDomain(first: a, last: date(2026, 12, 31), allowed: allowed)
      }
    }
    #expect(throws: WireError.limitExceeded) {
      _ = try CivilDateDomain(first: a, last: b, allowed: Array(repeating: a, count: 65536))
    }
  }
}
