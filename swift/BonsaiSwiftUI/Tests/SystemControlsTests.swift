import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func systemList(_ id: UInt64 = 1) -> WireOperation {
    operation(OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(80))
      $0.integer(UInt16(0))
    }
  }
  static func systemSection(_ id: UInt64, separator: UInt8 = 0) -> WireOperation {
    operation(OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(81))
      $0.integer(UInt8(1))
      $0.integer(UInt8(1))
      $0.integer(separator)
      $0.integer(UInt16(0))
    }
  }
  static func systemRow(_ id: UInt64, separator: UInt8 = 0) -> WireOperation {
    operation(OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(82))
      $0.integer(separator)
      $0.integer(UInt16(0))
    }
  }
  static func systemListFrame() -> [WireOperation] {
    [
      systemList(), systemSection(2), text(3, "Header"), text(4, "Footer"),
      systemRow(5), text(6, "First row"), systemRow(7, separator: 2), text(8, "Second row"),
      children(5, [6]), children(7, [8]), children(2, [3, 4, 5, 7]), children(1, [2]), root(1),
    ]
  }
}

@MainActor struct SystemControlsTests {
  @Test func listRetainsRowsAcrossReorderingAndRejectsMalformedComposition() throws {
    let tree = RenderTree()
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.systemListFrame())).tree
    tree.commit(store)
    let first = try #require(tree.nodes[5])
    let reordered = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.children(2, [3, 4, 7, 5])
        ], base: 1, revision: 2)
    ).tree
    tree.commit(reordered)
    #expect(tree.nodes[5] === first)
    for invalid in [
      TreeFixture.children(1, [5]), TreeFixture.children(2, [3, 4, 6]),
      TreeFixture.children(5, []), TreeFixture.children(5, [6, 8]),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([invalid], base: 1, revision: 2))
      }
    }
    #expect(store.revision == 1)
  }

  @Test func listVisibilityCoalescesAndResendsForANewHandlerOrOrder() throws {
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(TreeFixture.systemListFrame())).tree)
    let first = try #require(tree.nodes[5]?.id)
    let second = try #require(tree.nodes[7]?.id)
    let visibility = try #require(tree.root?.listVisibility)
    visibility.synchronize([first, second], handler: 91)
    visibility.update(second, visible: true)
    #expect(visibility.request == 1..<2)
    visibility.accepted(1..<2)
    #expect(visibility.request == nil)
    visibility.synchronize([first, second], handler: 92)
    #expect(visibility.request == 1..<2)
    visibility.accepted(1..<2)
    visibility.synchronize([second, first], handler: 92)
    #expect(visibility.request == 0..<1)
    visibility.synchronize([first], handler: 92)
    #expect(visibility.request == nil)
    visibility.update(second, visible: true)
    #expect(visibility.request == nil)
  }

  @Test func hostedListExposesRowsAndSectionLabelsWithoutARefreshButtonRow() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(TreeFixture.systemListFrame())).tree)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 400, height: 400),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    func cellElements(_ view: NSView) -> [AccessibilityElement] {
      if let outline = view as? NSOutlineView {
        return (0..<outline.numberOfRows).flatMap { row in
          outline.view(atColumn: 0, row: row, makeIfNecessary: false).map(accessibilityElements)
            ?? []
        }
      }
      return view.subviews.flatMap(cellElements)
    }
    let elements = accessibilityElements(host) + cellElements(host)
    for label in ["Header", "Footer", "First row", "Second row"] {
      #expect(elements.contains { $0.label == label || $0.value == label })
    }
    #expect(!elements.contains { $0.role == "AXButton" && $0.label == "Refresh" })
  }

  @Test func nativeLinearProgressMatchesSystemPresentation() throws {
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.progress(value: 0.4, style: 0), TreeFixture.root(1),
        ])
      ).tree)
    let actual = try raster(
      NativeNodeView(node: try #require(tree.root), activate: { _ in })
        .tint(.blue).frame(width: 180, height: 40))
    let expected = try raster(
      ProgressView(value: 0.4).progressViewStyle(.linear)
        .tint(.blue).frame(width: 180, height: 40))
    #expect(actual.matches(expected))
  }

  @Test func progressRejectsUnsupportedModesInsteadOfChangingTheirMeaning() throws {
    for (value, style) in [(Optional(0.4), UInt8(1)), (nil, UInt8(0))] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(
          TreeFixture.frame([
            TreeFixture.progress(value: value, style: style), TreeFixture.root(1),
          ]))
      }
    }
    _ = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.progress(style: 2), TreeFixture.root(1),
      ]))
  }

  @Test func ordinaryDateControlHostsASystemDatePicker() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.civilDateControl(), TreeFixture.root(1),
        ])
      ).tree)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    func containsDatePicker(_ view: NSView) -> Bool {
      view is NSDatePicker || view.subviews.contains(where: containsDatePicker)
    }
    #expect(containsDatePicker(host))
  }
}
