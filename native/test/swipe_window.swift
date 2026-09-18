import AppKit
import Observation
import SwiftUI

@MainActor @Observable final class SwipeWindowModel {
  let tree = RenderTree()
  var events: [UInt64] = []
  let rtl = CommandLine.arguments.contains("--rtl")
  let refresh = CommandLine.arguments.contains("--refresh")
  init() {
    var operations = TreeFixture.swipeTree()
    if refresh {
      operations += [
        TreeFixture.operation(OperationId.createNode) {
          $0.integer(UInt64(20))
          $0.integer(UInt16(NodeKindId.refresh))
          $0.integer(Int64(1))
          $0.integer(UInt8(0))
          $0.integer(UInt8(0))
          $0.integer(UInt16(1))
          $0.integer(UInt16(EventTagId.refreshRequest))
          $0.integer(UInt64(100))
        }, TreeFixture.children(20, [10]), TreeFixture.root(20),
      ]
    }
    tree.commit(try! NodeStore().staging(TreeFixture.frame(operations)).tree)
    tree.root?.refreshController?.setPresentation(presented: true, active: true)
    tree.onInput = { [weak self] node, _ in
      self?.events.append(node.id.node)
      return true
    }
  }
}
@main struct SwipeWindowAcceptance: App {
  @State private var model = SwipeWindowModel()
  var body: some Scene {
    Window("Swipe Acceptance", id: "swipe") {
      NativeNodeView(node: model.tree.root!, activate: { _ in })
        .frame(width: 400, height: 300)
        .environment(\.layoutDirection, model.rtl ? .rightToLeft : .leftToRight)
        .environment(\.scenePhase, .active)
        .task { await verify(model) }
    }.defaultSize(width: 400, height: 300)
  }
}
@MainActor private func verify(_ model: SwipeWindowModel) async {
  do {
    let window = try require(NSApp.windows.first(where: { $0.contentView != nil }))
    let host = try require(window.contentView)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    try await settleAccessibility(host)
    func outlines(_ view: NSView) -> [NSOutlineView] {
      (view as? NSOutlineView).map { [$0] } ?? view.subviews.flatMap(outlines)
    }
    let list = try require(outlines(host).first)
    let table: NSTableView = list
    let row = try require(
      (0..<list.numberOfRows).first { row in
        !(table.delegate?.tableView?(table, rowActionsForRow: row, edge: .leading) ?? []).isEmpty
      })
    let leading = table.delegate?.tableView?(table, rowActionsForRow: row, edge: .leading) ?? []
    let trailing = table.delegate?.tableView?(table, rowActionsForRow: row, edge: .trailing) ?? []
    guard leading.map(\.title) == ["Archive"], trailing.map(\.title) == ["Mark read"] else {
      throw error("System row actions lost their edge or identity")
    }
    if model.refresh {
      let buttons =
        window.toolbar?.items.flatMap { item in
          item.view.map(accessibilityElements) ?? []
        } ?? []
      let refresh = try require(buttons.first { $0.role == "AXButton" && $0.label == "Refresh" })
      guard refresh.press() else { throw error("Native toolbar rejected refresh") }
      try await settleAccessibility(host)
      guard model.events == [20], list.numberOfRows == 2 else {
        throw error("Refresh duplicated its request or inserted a row: \(model.events)")
      }
      model.tree.root?.refreshController?.synchronize(RenderRefresh(token: 1, state: 2, show: nil))
    }
    print("PASS: native List swipe actions")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func error(_ text: String) -> NSError {
  NSError(domain: "SwipeWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
private func require<T>(_ value: T?) throws -> T {
  guard let value else { throw error("Missing native object") }
  return value
}
