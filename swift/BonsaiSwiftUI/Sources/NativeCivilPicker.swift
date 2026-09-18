import Observation
import SwiftUI

enum CivilSelection: Equatable, Sendable {
  case date(CivilDate)
  case time(CivilTime)
  var payload: NativeEventPayload {
    switch self {
    case .date(let value): .civilDate(value)
    case .time(let value): .civilTime(value)
    }
  }
}

extension NativeEventPayload {
  var civilSelection: CivilSelection? {
    switch self {
    case .civilDate(let value): .date(value)
    case .civilTime(let value): .time(value)
    default: nil
    }
  }
}

enum RenderCivilPicker: Equatable, Sendable {
  case date(selection: CivilDate, domain: CivilDateDomain, label: String, enabled: Bool)
  case time(selection: CivilTime, format: CivilTimeFormat, label: String, enabled: Bool)
  var selection: CivilSelection {
    switch self {
    case .date(let value, _, _, _): .date(value)
    case .time(let value, _, _, _): .time(value)
    }
  }
  var enabled: Bool {
    switch self {
    case .date(_, _, _, let value), .time(_, _, _, let value): value
    }
  }
  var label: String {
    switch self {
    case .date(_, _, let value, _), .time(_, _, let value, _): value
    }
  }
  var tag: Int { selection.payload.tag }
  func admits(_ value: CivilSelection) -> Bool {
    guard enabled else { return false }
    switch (self, value) {
    case (.date(_, let domain, _, _), .date(let value)): return domain.contains(value)
    case (.time, .time(let value)): return value.isValid
    default: return false
    }
  }
  func sameConfiguration(as other: Self) -> Bool {
    switch (self, other) {
    case (
      .date(_, let a, let label, let enabled), .date(_, let b, let otherLabel, let otherEnabled)
    ):
      a == b && label == otherLabel && enabled == otherEnabled
    case (
      .time(_, let a, let label, let enabled), .time(_, let b, let otherLabel, let otherEnabled)
    ):
      a == b && label == otherLabel && enabled == otherEnabled
    default: false
    }
  }
  static func decode(_ reader: inout WireReader, date: Bool) throws -> Self {
    func readDate(_ reader: inout WireReader) throws -> CivilDate {
      CivilDate(
        year: Int(try reader.integer(UInt16.self)), month: Int(try reader.integer(UInt8.self)),
        day: Int(try reader.integer(UInt8.self)))
    }
    let result: Self
    if date {
      let selected = try readDate(&reader)
      let first = try readDate(&reader)
      let last = try readDate(&reader)
      let domain = try CivilDateDomain(first: first, last: last)
      guard domain.contains(selected) else { throw TreeError.invalidProperties }
      result = .date(
        selection: selected, domain: domain, label: try reader.string(), enabled: try reader.flag())
    } else {
      let selected = CivilTime(
        hour: Int(try reader.integer(UInt8.self)), minute: Int(try reader.integer(UInt8.self)))
      guard selected.isValid else { throw TreeError.invalidProperties }
      let format = CivilTimeFormat(rawValue: try reader.choice(2))!
      result = .time(
        selection: selected, format: format, label: try reader.string(), enabled: try reader.flag())
    }
    guard !result.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TreeError.invalidProperties
    }
    return result
  }
}

@MainActor @Observable final class CivilPickerController {
  struct Request: Equatable {
    let serial: UInt64
    let value: CivilSelection
  }
  private(set) var selection: CivilSelection
  private(set) var pending: Request?
  private var properties: RenderCivilPicker
  private var generation: UInt64 = 0
  private var serial: UInt64 = 0
  private var disposed = false
  init(_ properties: RenderCivilPicker) {
    self.properties = properties
    selection = properties.selection
  }
  func synchronize(_ next: RenderCivilPicker) {
    if !next.sameConfiguration(as: properties) {
      pending = nil
      generation += 1
    }
    properties = next
    let visible = pending?.value ?? next.selection
    if visible != selection { generation += 1 }
    selection = visible
  }
  func resolve(_ request: Request) {
    guard pending == request else { return }
    pending = nil
    if selection != properties.selection { generation += 1 }
    selection = properties.selection
  }
  @discardableResult func request(_ value: CivilSelection, emit: (NativeEventPayload) -> Bool)
    -> Bool
  {
    guard !disposed, properties.admits(value), selection != value else { return false }
    guard emit(value.payload) else {
      generation += 1
      return false
    }
    serial += 1
    pending = Request(serial: serial, value: value)
    selection = value
    return true
  }
  private final class BindingRead {
    var generation: UInt64
    init(_ generation: UInt64) { self.generation = generation }
  }
  func dateBinding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<Date> {
    let read = BindingRead(generation)
    return Binding(
      get: {
        read.generation = self.generation
        guard case .date(let value) = self.selection else {
          preconditionFailure("Date binding on a time control")
        }
        return try! value.dateForPicker()
      },
      set: { date in
        guard read.generation == self.generation, let value = try? CivilDate.fromPickerDate(date)
        else { return }
        self.request(.date(value), emit: emit)
      })
  }
  func timeBinding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<Date> {
    let read = BindingRead(generation)
    return Binding(
      get: {
        read.generation = self.generation
        guard case .time(let value) = self.selection else {
          preconditionFailure("Time binding on a date control")
        }
        return try! value.dateForPicker()
      },
      set: { date in
        guard read.generation == self.generation, let value = try? CivilTime.fromPickerDate(date)
        else { return }
        self.request(.time(value), emit: emit)
      })
  }
  func invalidateBinding() {
    pending = nil
    generation += 1
    selection = properties.selection
  }
  func dispose() {
    disposed = true
    pending = nil
    generation += 1
  }
}

struct NativeCivilPicker: View {
  let node: RenderNodeState
  let properties: RenderCivilPicker
  let controller: CivilPickerController
  @Environment(\.locale) private var locale
  @ViewBuilder var body: some View {
    switch properties {
    case .date(_, let domain, let label, let enabled):
      DatePicker(
        label, selection: controller.dateBinding(emit: node.emit),
        in: domain.pickerRange, displayedComponents: .date
      )
      .environment(\.calendar, CivilDate.pickerCalendar)
      .environment(\.timeZone, .gmt)
      .disabled(!enabled)
    case .time(_, let format, let label, let enabled):
      DatePicker(
        label, selection: controller.timeBinding(emit: node.emit),
        displayedComponents: .hourAndMinute
      )
      .modifier(NativeInteractiveBounds())
      .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
      .environment(\.locale, format.applying(to: locale))
      .disabled(!enabled)
    }
  }
}
