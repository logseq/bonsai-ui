import SwiftUI

/// Civil component values stay independent of time zones and Gregorian cutover dates.
enum HostPickerContent: Equatable, Sendable {
  case date(CivilDate, CivilDateDomain)
  case range(CivilDate, CivilDate, CivilDateDomain)
  case time(CivilTime, CivilTimeFormat)

  static func decode(kind: Int, reader: inout WireReader) throws -> Self {
    func date(_ reader: inout WireReader) throws -> CivilDate {
      let year = Int(try reader.integer(UInt16.self))
      let month = Int(try reader.integer(UInt8.self))
      let day = Int(try reader.integer(UInt8.self))
      let value = CivilDate(year: year, month: month, day: day)
      guard value.isValid else { throw WireError.invalidOperation }
      return value
    }
    if kind == HostRequestId.pickTime {
      let hour = Int(try reader.integer(UInt8.self))
      let minute = Int(try reader.integer(UInt8.self))
      let value = CivilTime(hour: hour, minute: minute)
      guard value.isValid,
        let format = CivilTimeFormat(rawValue: Int(try reader.integer(UInt8.self)))
      else { throw WireError.invalidOperation }
      return .time(value, format)
    }
    let hasInitial = try reader.flag()
    let start = try hasInitial ? date(&reader) : nil
    let end = try hasInitial && kind == HostRequestId.pickDateRange ? date(&reader) : nil
    let first = try date(&reader)
    let last = try date(&reader)
    let domain = try CivilDateDomain(first: first, last: last)
    let selectedStart = start ?? first
    let selectedEnd = end ?? selectedStart
    guard domain.contains(selectedStart), domain.contains(selectedEnd), selectedStart <= selectedEnd
    else { throw WireError.invalidOperation }
    return kind == HostRequestId.pickDateRange
      ? .range(selectedStart, selectedEnd, domain) : .date(selectedStart, domain)
  }

  func response(_ selection: HostPickerContent) throws -> Data {
    var writer = WireWriter()
    writer.integer(UInt8(1))
    func write(_ value: CivilDate, to writer: inout WireWriter) {
      writer.integer(UInt16(value.year))
      writer.integer(UInt8(value.month))
      writer.integer(UInt8(value.day))
    }
    switch (self, selection) {
    case (.date(_, let domain), .date(let value, _)) where domain.contains(value):
      write(value, to: &writer)
    case (.range(_, _, let domain), .range(let start, let end, _))
    where domain.contains(start) && domain.contains(end) && start <= end:
      write(start, to: &writer)
      write(end, to: &writer)
    case (.time, .time(let value, _)) where value.isValid:
      writer.integer(UInt8(value.hour))
      writer.integer(UInt8(value.minute))
    default: throw WireError.invalidOperation
    }
    return writer.bytes
  }
}

private struct HostDateFields: View {
  let title: String
  let domain: CivilDateDomain
  @Binding var value: CivilDate

  private func binding(_ field: CivilPickerController.Field) -> Binding<Int> {
    let snapshot = value
    return Binding(
      get: {
        switch field {
        case .year: snapshot.year
        case .month: snapshot.month
        case .day: snapshot.day
        }
      },
      set: { proposed in
        guard value == snapshot else { return }
        let next: CivilDate?
        switch field {
        case .year: next = domain.selectingYear(proposed, from: snapshot)
        case .month: next = domain.selectingMonth(proposed, from: snapshot)
        case .day: next = domain.selectingDay(proposed, from: snapshot)
        }
        if let next { value = next }
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.headline)
      HStack {
        Picker("Year", selection: binding(.year)) {
          ForEach(domain.years, id: \.self) { Text(String($0)).tag($0) }
        }.accessibilityLabel(title + " year")
        Picker("Month", selection: binding(.month)) {
          ForEach(domain.months(in: value.year), id: \.self) { Text(String($0)).tag($0) }
        }.accessibilityLabel(title + " month")
        Picker("Day", selection: binding(.day)) {
          ForEach(domain.days(in: value.year, month: value.month), id: \.self) {
            Text(String($0)).tag($0)
          }
        }.accessibilityLabel(title + " day")
      }.pickerStyle(.menu).labelsHidden()
    }
  }
}

struct NativeHostPickerForm: View {
  let complete: (HostPickerContent?) -> Void
  @Environment(\.locale) private var locale
  @State private var draft: HostPickerContent
  init(initial: HostPickerContent, complete: @escaping (HostPickerContent?) -> Void) {
    self.complete = complete
    _draft = State(initialValue: initial)
  }
  var body: some View {
    VStack(spacing: 16) {
      switch draft {
      case .date(let value, let domain):
        HostDateFields(
          title: "Date", domain: domain,
          value: Binding(
            get: {
              if case .date(let current, _) = draft { return current }
              return value
            },
            set: { if draft == .date(value, domain) { draft = .date($0, domain) } }))
      case .range(let start, let end, let domain):
        HostDateFields(
          title: "Start", domain: domain,
          value: Binding(
            get: {
              if case .range(let current, _, _) = draft { return current }
              return start
            },
            set: {
              if draft == .range(start, end, domain) { draft = .range($0, max($0, end), domain) }
            }))
        // A valid start always admits a nonempty inclusive end domain.
        if let endDomain = try? CivilDateDomain(first: start, last: domain.last) {
          HostDateFields(
            title: "End", domain: endDomain,
            value: Binding(
              get: {
                if case .range(_, let current, _) = draft { return current }
                return end
              },
              set: { if draft == .range(start, end, domain) { draft = .range(start, $0, domain) } })
          )
        }
      case .time(let value, let format):
        if let date = try? value.dateForPicker() {
          DatePicker(
            "Time",
            selection: Binding(
              get: { date },
              set: { proposed in
                guard draft == .time(value, format) else { return }
                if let value = try? CivilTime.fromPickerDate(proposed) {
                  draft = .time(value, format)
                }
              }), displayedComponents: .hourAndMinute
          )
          .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
          .environment(\.locale, format.applying(to: locale))
        }
      }
      HStack {
        Button("Cancel", role: .cancel) { complete(nil) }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save") { complete(draft) }.keyboardShortcut(.defaultAction)
      }
    }.padding(16).frame(minWidth: 240, idealWidth: 320, maxWidth: 340)
  }
}
