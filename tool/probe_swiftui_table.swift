import Observation
import SwiftUI

// Independent Apple API diagnostic; not linked to Bonsai or evidence of a migrated Table.
#if os(macOS)
  import AppKit
#endif

struct ProbeRow: Identifiable {
  let id: Int
  let rank: Int
}
struct ProbeColumn: Identifiable {
  let id: Int
  let title: String
  let sortable: Bool
}
struct ProbeSort: SortComparator {
  let columnID: Int
  var order: SortOrder = .forward
  func compare(_ lhs: ProbeRow, _ rhs: ProbeRow) -> ComparisonResult {
    if lhs.rank == rhs.rank { return .orderedSame }
    return (lhs.rank < rhs.rank) == (order == .forward) ? .orderedAscending : .orderedDescending
  }
}
@MainActor @Observable final class ProbeModel {
  var selected = Set<Int>()
  var sorting = [ProbeSort]()
  var activated: Int?
  var rejectSelection = false
  var rejectSort = false
  var resolution = 0
  var selectionRequests = [Set<Int>]()
  var sortRequests = [[ProbeSort]]()
  var rows = [ProbeRow(id: -7, rank: 0), ProbeRow(id: 9, rank: 1), ProbeRow(id: 13, rank: 2)]
  var columns = [
    ProbeColumn(id: 1, title: "Name", sortable: true),
    ProbeColumn(id: 2, title: "Action", sortable: false),
    ProbeColumn(id: 3, title: "Rank", sortable: true),
  ]
}
struct ProbeTable: View {
  @Bindable var model: ProbeModel
  @TableColumnBuilder<ProbeRow, ProbeSort>
  func column(_ column: ProbeColumn) -> some TableColumnContent<ProbeRow, ProbeSort> {
    if column.sortable {
      TableColumn(column.title, sortUsing: ProbeSort(columnID: column.id)) { row in
        Text(column.id == 1 ? "Row \(row.id)" : "Rank \(row.rank)")
      }.width(min: 150)
    }
    if !column.sortable {
      TableColumn(column.title) { (row: ProbeRow) in
        Button("Open \(row.id)") { model.activated = row.id }
      }.width(min: 150)
    }
  }
  var body: some View {
    Table(
      of: ProbeRow.self,
      selection: Binding(
        get: {
          _ = model.resolution
          return model.selected
        },
        set: {
          model.selectionRequests.append($0)
          if !model.rejectSelection { model.selected = $0 }
          model.resolution += 1
        }),
      sortOrder: Binding(
        get: {
          _ = model.resolution
          return model.sorting
        },
        set: {
          model.sortRequests.append($0)
          if !model.rejectSort { model.sorting = $0 }
          model.resolution += 1
        })
    ) {
      TableColumnForEach(model.columns) { column($0) }
    } rows: {
      ForEach(model.rows) { row in
        TableRow(row).selectionDisabled(row.id == 9)
      }
    }
  }
}
#if os(macOS)
  @main struct ProbeApplication: App {
    @State private var model = ProbeModel()
    var body: some Scene {
      Window("Table diagnostic", id: "table") {
        ProbeTable(model: model).frame(minWidth: 700, minHeight: 400)
          .task { await run(model) }
      }.defaultSize(width: 700, height: 400)
    }
  }
  @MainActor func descendants<T: NSView>(_ root: NSView, _: T.Type) -> [T] {
    (root as? T).map { [$0] } ?? root.subviews.flatMap { descendants($0, T.self) }
  }
  private func require(_ condition: Bool, _ message: String) throws {
    if !condition {
      throw NSError(
        domain: "TableAPIProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  @MainActor func run(_ model: ProbeModel) async {
    do {
      guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
        let host = window.contentView
      else { throw NSError(domain: "TableAPIProbe", code: 2) }
      for _ in 0..<3 { try await settleAccessibility(host) }
      guard let table = descendants(host, NSOutlineView.self).first else {
        throw NSError(domain: "TableAPIProbe", code: 3)
      }
      func renderedNames() -> [String] {
        (0..<table.numberOfRows).compactMap { row in
          guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) else {
            return nil
          }
          return accessibilityElements(cell).first { $0.role == "AXStaticText" }?.value
        }
      }
      func nativeSelection() -> Set<Int> {
        Set(table.selectedRowIndexes.map { model.rows[$0].id })
      }
      try require(
        table.tableColumns.map(\.title) == ["Name", "Action", "Rank"], "Dynamic column order")
      try require(
        table.tableColumns.map { $0.sortDescriptorPrototype != nil } == [true, false, true],
        "Mixed column sortability")
      try require(renderedNames() == ["Row -7", "Row 9", "Row 13"], "Native initial cell content")
      for row in 0..<table.numberOfRows {
        guard let item = table.item(atRow: row) else {
          throw NSError(domain: "TableAPIProbe", code: 4)
        }
        try require(
          table.delegate?.outlineView?(table, shouldSelectItem: item) == (row != 1),
          "Native selection eligibility")
      }
      guard let disabledCell = table.view(atColumn: 1, row: 1, makeIfNecessary: true),
        let button = accessibilityElements(disabledCell).first(where: { $0.role == "AXButton" })
      else { throw NSError(domain: "TableAPIProbe", code: 5) }
      try require(
        button.enabled && button.press(), "Disabled-selection row must retain its cell action")
      try await settleAccessibility(host)
      try require(model.activated == 9, "Cell action did not reach the application")

      // These native setters exercise SwiftUI binding plumbing, not mouse/keyboard gestures.
      table.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
      try await settleAccessibility(host)
      try require(model.selected == [-7, 13], "Native multiple selection binding")
      model.rejectSelection = true
      let selectionRequestCount = model.selectionRequests.count
      table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
      try await settleAccessibility(host)
      try require(model.selectionRequests.count > selectionRequestCount, "Missing selection intent")
      try require(
        model.selected == [-7, 13] && nativeSelection() == model.selected,
        "Rejected selection did not restore native state")

      model.selected = [-7]
      model.rows.reverse()
      try await settleAccessibility(host)
      try require(
        renderedNames() == ["Row 13", "Row 9", "Row -7"], "Canonical row order not rendered")
      try require(
        table.selectedRowIndexes == IndexSet(integer: 2),
        "Selection did not follow stable row identity")
      guard let rankSort = table.tableColumns[2].sortDescriptorPrototype,
        let nameSort = table.tableColumns[0].sortDescriptorPrototype
      else { throw NSError(domain: "TableAPIProbe", code: 6) }
      table.sortDescriptors = [rankSort]
      try await settleAccessibility(host)
      try require(
        model.sorting.count == 1 && model.sorting[0].columnID == 3
          && model.sorting[0].order == .forward, "Native sort intent")
      try require(
        renderedNames() == ["Row 13", "Row 9", "Row -7"],
        "Native Table unexpectedly sorted business data")
      let acceptedDescriptors = table.sortDescriptors
      model.rejectSort = true
      let sortRequestCount = model.sortRequests.count
      table.sortDescriptors = [nameSort]
      try await settleAccessibility(host)
      try require(model.sortRequests.count > sortRequestCount, "Missing rejected sort intent")
      try require(model.sorting[0].columnID == 3, "Rejected sort changed canonical intent")
      try require(
        table.sortDescriptors == acceptedDescriptors,
        "Rejected sort did not restore native descriptor")

      model.columns = [
        model.columns[2], model.columns[1], ProbeColumn(id: 4, title: "Extra", sortable: false),
      ]
      try await settleAccessibility(host)
      try require(
        descendants(host, NSOutlineView.self).first === table,
        "Column mutation recreated native Table")
      try require(
        table.tableColumns.map(\.title) == ["Rank", "Action", "Extra"],
        "Column insertion/removal/reorder")
      try require(
        table.tableColumns.map { $0.sortDescriptorPrototype != nil } == [true, false, false],
        "Mutated column sortability")
      try require(nativeSelection() == [-7], "Column mutation lost canonical selection")
      print(
        "PASS: dynamic mixed columns, native cell action, eligibility, binding restoration, canonical order and stable selection"
      )
      fflush(stdout)
      exit(0)
    } catch {
      print("FAIL: \(error)")
      fflush(stdout)
      exit(1)
    }
  }
#endif
