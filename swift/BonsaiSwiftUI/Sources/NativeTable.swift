import Observation
import SwiftUI

struct RenderTable: Equatable, Sendable {
  struct Column: Equatable, Identifiable, Sendable {
    let id: Int64
    let title: String
    let hasDetails: Bool
    let help: String?
    let numeric: Bool
    let sortable: Bool
  }
  struct Row: Equatable, Identifiable, Sendable {
    let id: Int64
    let selectionEnabled: Bool
    let rank: Int
  }
  struct Sorting: Equatable, Sendable {
    let column: Int64
    let ascending: Bool
  }
  let columns: [Column]
  let rows: [Row]
  let columnIndices: [Int64: Int]
  let sortableIDs: Set<Int64>
  let selectableIDs: Set<Int64>
  let sorting: Sorting?
  let selected: Set<Int64>
  let hasSort: Bool
  let hasSelection: Bool
  var childCount: Int { columns.count * (rows.count + 1) }
  func sameConfiguration(as other: Self) -> Bool {
    columns == other.columns && rows == other.rows && hasSort == other.hasSort
      && hasSelection == other.hasSelection
  }
  func admits(_ payload: NativeEventPayload) -> Bool {
    switch payload {
    case .tableSort(let id, _): return hasSort && sortableIDs.contains(id)
    case .tableSelection(let id, _):
      return hasSelection && selectableIDs.contains(id)
    default: return false
    }
  }
  static func decode(_ reader: inout WireReader) throws -> Self {
    func nonempty(_ text: String) -> Bool {
      !text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{000C}")).isEmpty
    }
    let columnCount = Int(try reader.integer(UInt16.self))
    guard columnCount > 0 else { throw TreeError.invalidProperties }
    var columnIDs = Set<Int64>()
    var columns: [Column] = []
    for _ in 0..<columnCount {
      let id = Int64(bitPattern: try reader.integer(UInt64.self))
      let title = try reader.string()
      let hasDetails = try reader.flag()
      let help = try reader.flag() ? reader.string() : nil
      let numeric = try reader.flag()
      let sortable = try reader.flag()
      guard columnIDs.insert(id).inserted, nonempty(title), help.map(nonempty) ?? true else {
        throw TreeError.invalidProperties
      }
      columns.append(
        Column(
          id: id, title: title, hasDetails: hasDetails, help: help, numeric: numeric,
          sortable: sortable))
    }
    let rowCount = Int(try reader.integer(UInt16.self))
    var rowIDs = Set<Int64>()
    var rows: [Row] = []
    for rank in 0..<rowCount {
      let id = Int64(bitPattern: try reader.integer(UInt64.self))
      guard rowIDs.insert(id).inserted else { throw TreeError.invalidProperties }
      rows.append(Row(id: id, selectionEnabled: try reader.flag(), rank: rank))
    }
    let sortColumn = try reader.flag() ? Int64(bitPattern: reader.integer(UInt64.self)) : nil
    let ascending = try reader.flag()
    if let sortColumn {
      guard columns.contains(where: { $0.id == sortColumn && $0.sortable }) else {
        throw TreeError.invalidProperties
      }
    }
    var selected = Set<Int64>()
    var previous: Int64?
    for _ in 0..<Int(try reader.integer(UInt16.self)) {
      let id = Int64(bitPattern: try reader.integer(UInt64.self))
      guard rowIDs.contains(id), previous.map({ $0 < id }) ?? true else {
        throw TreeError.invalidProperties
      }
      selected.insert(id)
      previous = id
    }
    return Self(
      columns: columns, rows: rows,
      columnIndices: Dictionary(
        uniqueKeysWithValues: columns.enumerated().map { ($0.element.id, $0.offset) }),
      sortableIDs: Set(columns.filter(\.sortable).map(\.id)),
      selectableIDs: Set(rows.filter(\.selectionEnabled).map(\.id)),
      sorting: sortColumn.map { Sorting(column: $0, ascending: ascending) }, selected: selected,
      hasSort: try reader.flag(), hasSelection: try reader.flag())
  }
}

@MainActor @Observable final class NativeTableController {
  struct Request {
    let serial: UInt64
    let payload: NativeEventPayload
  }
  private(set) var pending: [Request] = []
  @ObservationIgnored var onPresentationChange: (() -> Void)?
  var detailsExpanded = false {
    didSet { if oldValue != detailsExpanded { onPresentationChange?() } }
  }
  private var properties: RenderTable
  private var serial: UInt64 = 0
  private var generation: UInt64 = 0
  private var resolution: UInt64 = 0
  private var disposed = false
  init(_ properties: RenderTable) { self.properties = properties }
  var selection: Set<Int64> {
    _ = resolution
    var value = properties.selected
    for request in pending {
      if case .tableSelection(let id, let selected) = request.payload {
        if selected { value.insert(id) } else { value.remove(id) }
      }
    }
    return value
  }
  var sorting: RenderTable.Sorting? {
    _ = resolution
    for request in pending.reversed() {
      if case .tableSort(let id, let ascending) = request.payload {
        return .init(column: id, ascending: ascending)
      }
    }
    return properties.sorting
  }
  func synchronize(_ next: RenderTable) {
    if !properties.sameConfiguration(as: next) { invalidateBinding() }
    properties = next
  }
  func invalidateBinding() {
    pending.removeAll()
    generation += 1
    resolution += 1
  }
  @discardableResult func request(_ payload: NativeEventPayload, emit: (NativeEventPayload) -> Bool)
    -> Bool
  {
    guard !disposed, properties.admits(payload), emit(payload) else {
      resolution += 1
      return false
    }
    serial += 1
    pending.append(Request(serial: serial, payload: payload))
    return true
  }
  func selectionBinding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<Set<Int64>> {
    let generation = generation
    return Binding(
      get: { self.selection },
      set: { selected in
        guard !self.disposed, self.generation == generation else { return }
        let previous = self.selection
        for id in previous.symmetricDifference(selected).sorted() {
          let payload = NativeEventPayload.tableSelection(id, selected.contains(id))
          guard self.properties.admits(payload) else { continue }
          if !self.request(payload, emit: emit) { break }
        }
        self.resolution += 1
      })
  }
  func sortAction(_ column: Int64, ascending: Bool, emit: @escaping (NativeEventPayload) -> Bool)
    -> () -> Void
  {
    let generation = generation
    return {
      guard !self.disposed, generation == self.generation else { return }
      self.request(.tableSort(column, ascending), emit: emit)
    }
  }
  func sortBinding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<[NativeTableSort]> {
    let generation = generation
    return Binding(
      get: {
        self.sorting.map {
          [NativeTableSort(column: $0.column, order: $0.ascending ? .forward : .reverse)]
        } ?? []
      },
      set: { sorting in
        guard !self.disposed, self.generation == generation, let first = sorting.first else {
          return
        }
        self.request(.tableSort(first.column, first.order == .forward), emit: emit)
      })
  }
  func resolve(_ request: Request) {
    pending.removeAll { $0.serial <= request.serial }
    resolution += 1
  }
  func dispose() {
    disposed = true
    invalidateBinding()
  }
}

struct NativeTableSort: SortComparator {
  let column: Int64
  var order: SortOrder = .forward
  func compare(_ lhs: RenderTable.Row, _ rhs: RenderTable.Row) -> ComparisonResult {
    if lhs.rank == rhs.rank { return .orderedSame }
    return (lhs.rank < rhs.rank) == (order == .forward) ? .orderedAscending : .orderedDescending
  }
}

struct NativeTable: View {
  let node: RenderNodeState
  let children: [RenderNodeState]
  let properties: RenderTable
  let controller: NativeTableController
  let activate: @MainActor (RenderNodeState) -> Void
  @Environment(\.horizontalSizeClass) private var sizeClass
  private func child(_ index: Int) -> some View {
    NativeNodeView(node: children[index], activate: activate)
  }
  private func cell(_ row: RenderTable.Row, _ column: RenderTable.Column) -> some View {
    let index = properties.columnIndices[column.id]!
    return child(properties.columns.count + row.rank * properties.columns.count + index)
      .frame(maxWidth: .infinity, alignment: column.numeric ? .trailing : .leading)
  }
  @TableColumnBuilder<RenderTable.Row, NativeTableSort>
  private func column(_ column: RenderTable.Column) -> some TableColumnContent<
    RenderTable.Row, NativeTableSort
  > {
    if column.sortable && properties.hasSort {
      TableColumn(column.title, sortUsing: NativeTableSort(column: column.id)) { row in
        cell(row, column)
      }
    }
    if !column.sortable || !properties.hasSort {
      TableColumn(column.title) { (row: RenderTable.Row) in cell(row, column) }
    }
  }
  private var details: some View {
    DisclosureGroup(
      "Column details",
      isExpanded: Binding(
        get: { controller.detailsExpanded }, set: { controller.detailsExpanded = $0 })
    ) {
      ForEach(Array(properties.columns.enumerated()), id: \.element.id) { index, column in
        VStack(alignment: .leading) {
          Text(column.title).font(.headline)
          if let help = column.help { Text(help) }
          if column.hasDetails { child(index) }
        }
      }
    }.padding(.horizontal)
  }
  private var compactTable: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        if properties.hasSort {
          ForEach(properties.columns.filter(\.sortable)) { column in
            HStack {
              Button(
                "Sort by \(column.title) ascending",
                action: controller.sortAction(column.id, ascending: true, emit: node.emit))
              Button(
                "Sort by \(column.title) descending",
                action: controller.sortAction(column.id, ascending: false, emit: node.emit))
            }
          }
        }
        ForEach(properties.rows) { row in
          GroupBox {
            VStack(alignment: .leading, spacing: 6) {
              if properties.hasSelection {
                let selected = controller.selectionBinding(emit: node.emit)
                Button {
                  var value = selected.wrappedValue
                  if value.contains(row.id) { value.remove(row.id) } else { value.insert(row.id) }
                  selected.wrappedValue = value
                } label: {
                  HStack {
                    Image(
                      systemName: selected.wrappedValue.contains(row.id)
                        ? "checkmark.circle.fill" : "circle")
                    Text(rowLabel(row))
                  }
                }.accessibilityLabel("Select " + rowLabel(row))
                  .accessibilityValue(
                    selected.wrappedValue.contains(row.id) ? "Selected" : "Not selected"
                  )
                  .disabled(!row.selectionEnabled)
              }
              ForEach(properties.columns) { column in
                VStack(alignment: .leading) {
                  Text(column.title).font(.caption).foregroundStyle(.secondary)
                  cell(row, column)
                }
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        if properties.rows.isEmpty { Text("No rows") }
      }.padding()
    }
  }
  private func rowLabel(_ row: RenderTable.Row) -> String {
    let index = properties.columns.count + row.rank * properties.columns.count
    if case .text(let text) = children[index].properties { return text.value }
    return String(row.id)
  }
  var body: some View {
    VStack(spacing: 8) {
      if properties.columns.contains(where: { $0.hasDetails || $0.help != nil }) { details }
      if sizeClass == .compact {
        compactTable
      } else {
        Table(
          of: RenderTable.Row.self, selection: controller.selectionBinding(emit: node.emit),
          sortOrder: controller.sortBinding(emit: node.emit)
        ) {
          TableColumnForEach(properties.columns) { column($0) }
        } rows: {
          ForEach(properties.rows) { row in
            TableRow(row).selectionDisabled(!properties.hasSelection || !row.selectionEnabled)
          }
        }
      }
    }
  }
}
