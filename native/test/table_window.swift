import AppKit
import SwiftUI

private let compact = ProcessInfo.processInfo.arguments.contains("--compact")

@main struct TableWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Table acceptance", id: "table-acceptance") {
      BonsaiApplicationView(entrypoint: "native-table", session: session)
        .environment(\.horizontalSizeClass, compact ? .compact : .regular)
        .frame(minWidth: compact ? 430 : 820, minHeight: 740)
        .task { await verify(session) }
    }.defaultSize(width: compact ? 430 : 820, height: 740)
  }
}

@MainActor private func descendants<T: NSView>(_ root: NSView, _: T.Type) -> [T] {
  (root as? T).map { [$0] } ?? root.subviews.flatMap { descendants($0, T.self) }
}
private func failure(_ text: String) -> NSError {
  NSError(domain: "TableWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let host = NSApp.windows.first(where: { $0.contentView != nil })?.contentView else {
      throw failure("Missing table window")
    }
    func contains(_ text: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let value) = $0.properties { return value.value == text }
        return false
      }
    }
    func wait(_ text: String) async throws {
      for _ in 0..<50 {
        try await settleAccessibility(host)
        if session.ticket == nil && contains(text) { return }
      }
      throw failure("Table state did not settle: \(text)")
    }
    func counter(_ prefix: String) -> Int {
      session.tree.nodes.values.compactMap { node -> Int? in
        guard case .text(let text) = node.properties, text.value.hasPrefix(prefix) else {
          return nil
        }
        return Int(text.value.dropFirst(prefix.count))
      }.first ?? 0
    }
    func waitForRequest(_ prefix: String, after previous: Int) async throws {
      for _ in 0..<50 {
        try await settleAccessibility(host)
        if session.ticket == nil && counter(prefix) > previous { return }
      }
      throw failure("Missing native request: " + prefix)
    }
    func elements() -> [AccessibilityElement] {
      var result = NSApp.windows.flatMap { accessibilityElements($0) }
      for table in descendants(host, NSTableView.self) {
        for row in 0..<table.numberOfRows {
          for column in 0..<table.numberOfColumns {
            if let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) {
              result += accessibilityElements(cell)
            }
          }
        }
      }
      return result
    }
    func control(_ title: String) throws -> AccessibilityElement {
      guard let found = elements().first(where: { $0.role == "AXButton" && $0.label == title })
      else {
        throw failure("Missing table control: \(title)")
      }
      return found
    }
    func press(_ title: String, until state: String) async throws {
      let button = try control(title)
      guard button.enabled && button.press() else { throw failure("Cannot press \(title)") }
      try await wait(state)
    }
    try await wait("Selected IDs: None")
    guard
      let disclosure = elements().first(where: {
        $0.role == "AXDisclosureTriangle" && $0.label?.contains("Column details") == true
      }), disclosure.press()
    else {
      throw failure("Missing column details disclosure")
    }
    try await settleAccessibility(host)
    let detailsAction = try control("Explain ranks")
    try await press("Explain ranks", until: "Opened ID: -7")
    guard disclosure.press() else { throw failure("Cannot close column details") }
    try await settleAccessibility(host)
    _ = detailsAction.press()
    try await settleAccessibility(host)
    guard contains("Opened count: 1") else {
      throw failure("Hidden column details accepted stale input")
    }

    if compact {
      // The compact presentation must expose all cell content, not only the first column.
      for value in ["First item", "Second item", "Unavailable item", "30", "10", "20"] {
        guard elements().contains(where: { $0.value == value || $0.label == value }) else {
          throw failure("Missing compact table value: \(value)")
        }
      }
      try await press("Select First item", until: "Selected IDs: -7")
      try await press("Select Second item", until: "Selected IDs: -7,9")
      guard try !control("Select Unavailable item").enabled else {
        throw failure("Disabled row selectable")
      }
      try await press("Sort by Rank ascending", until: "Order: 9,13,-7")
    } else {
      guard let table = descendants(host, NSOutlineView.self).first else {
        throw failure("Missing native Table")
      }
      guard table.tableColumns.map(\.title) == ["Name", "Rank", "Action"],
        table.tableColumns[2].sortDescriptorPrototype == nil
      else { throw failure("Wrong native columns") }
      guard let item = table.item(atRow: 2),
        table.delegate?.outlineView?(table, shouldSelectItem: item) == false
      else {
        throw failure("Disabled row accepts native selection")
      }
      table.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
      try await wait("Selected IDs: -7,9")
      guard let sort = table.tableColumns[1].sortDescriptorPrototype else {
        throw failure("Missing sort descriptor")
      }
      table.sortDescriptors = [sort]
      try await wait("Order: 9,13,-7")
      guard table.selectedRowIndexes == IndexSet([0, 2]) else {
        throw failure("Sorting lost selected row identity")
      }
    }
    try await press("Open Unavailable item", until: "Opened ID: 13")
    try await press("Reject table changes", until: "Changes rejected")
    try await press("Clear table selection", until: "Selected IDs: -7,9")
    if compact {
      try await press("Select Second item", until: "Selected IDs: -7,9")
    } else {
      guard let table = descendants(host, NSOutlineView.self).first else {
        throw failure("Table removed")
      }
      let previousSelection = counter("Selection requests: ")
      table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
      try await waitForRequest("Selection requests: ", after: previousSelection)
      for _ in 0..<3 { try await settleAccessibility(host) }
      guard table.selectedRowIndexes == IndexSet([0, 2]) else {
        throw failure("Rejected native selection not restored")
      }
      let previousSort = counter("Sort requests: ")
      table.sortDescriptors = [table.tableColumns[0].sortDescriptorPrototype!]
      try await waitForRequest("Sort requests: ", after: previousSort)
      guard contains("Order: 9,13,-7") else { throw failure("Rejected sort changed data") }
    }
    try await press("Accept table changes", until: "Changes accepted")
    try await press("Select all table rows", until: "Selected IDs: -7,9")
    try await press("Remove first table row", until: "Selected IDs: 9")
    try await press("Reorder table columns", until: "Columns reversed")
    try await press("Open Second item", until: "Opened ID: 9")
    try await press("Clear table rows", until: "Order: None")
    try await press("Reset table", until: "Order: -7,9,13")
    await session.close()
    print("PASS: real OCaml Table \(compact ? "compact" : "native")")
    fflush(stdout)
    exit(0)
  } catch {
    await session.close()
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
