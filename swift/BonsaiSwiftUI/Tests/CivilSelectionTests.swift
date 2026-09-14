import Foundation
import Testing

@testable import BonsaiSwiftUI

struct CivilSelectionTests {
  @Test func prolepticGregorianDatesRetainHistoricalDaysAndRejectInvalidComponents() {
    for (year, month, day) in [
      (1, 1, 1), (9999, 12, 31), (1582, 10, 10), (1600, 2, 29), (2000, 2, 29), (2024, 2, 29),
    ] {
      #expect(CivilDate(year: year, month: month, day: day).isValid)
    }
    for (year, month, day) in [
      (0, 1, 1), (10000, 1, 1), (1900, 2, 29), (2100, 2, 29), (1500, 2, 29), (2026, 4, 31),
      (2026, 0, 1), (2026, 13, 1), (2026, 1, 0), (Int.max, Int.max, Int.max),
      (Int.min, Int.min, Int.min),
    ] {
      #expect(!CivilDate(year: year, month: month, day: day).isValid)
    }
    #expect(CivilDate(year: 1582, month: 10, day: 10) < CivilDate(year: 1582, month: 10, day: 15))
  }

  @Test func civilClockValuesCoverMidnightNoonAndTheFinalMinute() {
    let allValid = (0..<24).allSatisfy { hour in
      (0..<60).allSatisfy { CivilTime(hour: hour, minute: $0).isValid }
    }
    #expect(allValid)
    for (hour, minute) in [(-1, 0), (24, 0), (0, -1), (0, 60), (Int.max, 0), (0, Int.min)] {
      #expect(!CivilTime(hour: hour, minute: minute).isValid)
    }
  }

  @Test func invalidCivilEventsAreRejectedBeforeQueueMutation() throws {
    var queue = NativeEventQueue()
    let valid = NativeEvent(
      sequence: 1, displayedRevision: 1, nodeID: 1, handlerID: 1,
      payload: .civilDate(CivilDate(year: 1582, month: 10, day: 10)))
    let accepted = queue.append(valid)
    #expect(accepted)
    let invalid: [NativeEventPayload] = [
      .civilDate(CivilDate(year: 1900, month: 2, day: 29)),
      .civilDate(CivilDate(year: -1, month: 1, day: 1)),
      .civilTime(CivilTime(hour: 24, minute: 0)), .civilTime(CivilTime(hour: 0, minute: -1)),
    ]
    for payload in invalid {
      let event = NativeEvent(
        sequence: 2, displayedRevision: 1, nodeID: 1, handlerID: 1, payload: payload)
      let rejected = !queue.append(event)
      #expect(rejected)
      #expect(throws: (any Error).self) { try EventBatch.encode(epoch: 1, events: [event]) }
    }
    #expect(queue.events.count == 1)
    #expect(queue.events.first?.payload == valid.payload)
  }

  @Test func consecutiveSelectionsKeepTheFinalValueWithoutCrossingBindingBoundaries() {
    var queue = NativeEventQueue()
    let date1 = NativeEventPayload.civilDate(CivilDate(year: 2026, month: 1, day: 1))
    let date2 = NativeEventPayload.civilDate(CivilDate(year: 2026, month: 2, day: 1))
    let time1 = NativeEventPayload.civilTime(CivilTime(hour: 0, minute: 0))
    let time2 = NativeEventPayload.civilTime(CivilTime(hour: 23, minute: 59))
    for (offset, payload) in [date1, date2, time1, time2, date1].enumerated() {
      let accepted = queue.append(
        NativeEvent(
          sequence: UInt64(offset + 1), displayedRevision: 1,
          nodeID: 1, handlerID: 1, payload: payload))
      #expect(accepted)
    }
    #expect(queue.events.map(\.payload) == [date2, time2, date1])
    let distinct = queue.append(
      NativeEvent(
        sequence: 6, displayedRevision: 1,
        nodeID: 1, handlerID: 2, payload: date2))
    #expect(distinct)
    #expect(queue.events.count == 4)
  }

  @Test func nativeTimeValuesRoundTripEveryMinuteAcrossDayBoundaries() throws {
    for minute in 0..<1440 {
      let value = CivilTime(hour: minute / 60, minute: minute % 60)
      let native = try value.dateForPicker()
      #expect(native.timeIntervalSinceReferenceDate == Double(minute * 60))
      #expect(try CivilTime.fromPickerDate(native) == value)
    }
    #expect(
      try CivilTime.fromPickerDate(Date(timeIntervalSinceReferenceDate: -60))
        == CivilTime(hour: 23, minute: 59))
    #expect(
      try CivilTime.fromPickerDate(Date(timeIntervalSinceReferenceDate: 86460))
        == CivilTime(hour: 0, minute: 1))
    for seconds in [Double.nan, .infinity, -.infinity] {
      #expect(throws: (any Error).self) {
        _ = try CivilTime.fromPickerDate(Date(timeIntervalSinceReferenceDate: seconds))
      }
    }
    #expect(throws: (any Error).self) { _ = try CivilTime(hour: 24, minute: 0).dateForPicker() }
  }

  @Test func hourCycleOverridePreservesLanguageRegionAndNumberingSystem() {
    for identifier in ["en_US", "fr_FR", "ar_EG@numbers=arab", "th_TH@calendar=buddhist"] {
      let locale = Locale(identifier: identifier)
      let original = Locale.Components(locale: locale)
      #expect(CivilTimeFormat.system.applying(to: locale) == locale)
      for (format, cycle) in [
        (CivilTimeFormat.hour12, Locale.HourCycle.oneToTwelve), (.hour24, .zeroToTwentyThree),
      ] {
        let changed = format.applying(to: locale)
        let components = Locale.Components(locale: changed)
        #expect(changed.hourCycle == cycle)
        #expect(components.languageComponents == original.languageComponents)
        #expect(components.numberingSystem == original.numberingSystem)
        #expect(components.calendar == original.calendar)
      }
    }
  }
}

extension NativeRuntimeTests {
  @Test func civilDateAndTimeEventsReachTheActualOcamlHandlers() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-civil-events")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      var bindings: [Int: (node: UInt64, handler: UInt64)] = [:]
      for operation in frame.operations where operation.opcode == OperationId.createNode {
        var reader = WireReader(operation.body)
        let node = try reader.integer(UInt64.self)
        let kind = Int(try reader.integer(UInt16.self))
        guard kind == NodeKindId.datePicker || kind == NodeKindId.timePicker else { continue }
        // Each of this fixture's two controls has exactly one civil binding.
        var binding = WireReader(Data(operation.body.suffix(12)))
        #expect(try binding.integer(UInt16.self) == 1)
        let tag = Int(try binding.integer(UInt16.self))
        let handler = try binding.integer(UInt64.self)
        if tag == 46 || tag == 47 { bindings[tag] = (node, handler) }
      }
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      let values: [NativeEventPayload] = [
        .civilDate(CivilDate(year: 1, month: 1, day: 1)),
        .civilDate(CivilDate(year: 1582, month: 10, day: 10)),
        .civilDate(CivilDate(year: 2000, month: 2, day: 29)),
        .civilDate(CivilDate(year: 9999, month: 12, day: 31)),
        .civilTime(CivilTime(hour: 0, minute: 0)),
        .civilTime(CivilTime(hour: 12, minute: 0)),
        .civilTime(CivilTime(hour: 23, minute: 59)),
      ]
      let events = try values.enumerated().map { index, value in
        let binding = try #require(bindings[value.tag])
        return NativeEvent(
          sequence: UInt64(index + 1), displayedRevision: frame.revision,
          nodeID: binding.node, handlerID: binding.handler, payload: value)
      }
      let bytes = try EventBatch.encode(epoch: frame.epoch, events: events)
      let updated = try await runtime.pump(monotonicNanoseconds: 3, events: bytes)
      let expected =
        "date:0001-01-01;date:1582-10-10;date:2000-02-29;date:9999-12-31;time:00:00;time:12:00;time:23:59;"
      #expect(updated.bytes.range(of: Data(expected.utf8)) != nil)
      try await runtime.acknowledge(updated, monotonicNanoseconds: 4)
      let replay = try await runtime.pump(monotonicNanoseconds: 5, events: bytes)
      #expect(replay.bytes.isEmpty)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
