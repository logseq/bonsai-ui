import Foundation
import Testing

@testable import BonsaiSwiftUI

struct CivilDateDomainTests {
  @Test func continuousDomainRejectsUnsupportedHistoryAndInvalidBoundaries() throws {
    let first = CivilDate(year: 2024, month: 2, day: 29)
    let last = CivilDate(year: 2025, month: 3, day: 10)
    let domain = try CivilDateDomain(first: first, last: last)
    #expect(domain.contains(first) && domain.contains(last))
    #expect(!domain.contains(CivilDate(year: 2025, month: 2, day: 29)))
    #expect(!domain.contains(CivilDate(year: 2024, month: 2, day: 28)))
    #expect(throws: (any Error).self) { try CivilDateDomain(first: last, last: first) }
    #expect(throws: (any Error).self) {
      try CivilDateDomain(first: CivilDate(year: 1582, month: 10, day: 10), last: last)
    }
  }
  @Test func pickerDatesRoundTripAcrossGregorianBoundariesWithoutLocalTimeZoneShifts() throws {
    for value in [
      CivilDate.pickerMinimum, CivilDate(year: 2000, month: 2, day: 29),
      CivilDate(year: 2024, month: 3, day: 10), CivilDate(year: 2024, month: 11, day: 3),
      CivilDate(year: 9999, month: 12, day: 31),
    ] {
      #expect(try CivilDate.fromPickerDate(value.dateForPicker()) == value)
    }
    for invalid in [
      CivilDate(year: 1500, month: 2, day: 29), CivilDate(year: 1582, month: 10, day: 10),
    ] {
      #expect(throws: (any Error).self) { try invalid.dateForPicker() }
    }
    #expect(throws: (any Error).self) {
      try CivilDate.fromPickerDate(Date(timeIntervalSinceReferenceDate: .infinity))
    }
  }
}
