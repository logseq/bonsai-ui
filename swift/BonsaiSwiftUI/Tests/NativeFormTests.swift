import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

private enum FormFixture {
  static func section(_ id: UInt64) -> WireOperation {
    TreeFixture.operation(OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(141))
      $0.bytes += [1, 1]
      $0.integer(UInt16(0))
    }
  }

  static func selection(_ enabled: UInt8 = 1, update: Bool = false) -> WireOperation {
    TreeFixture.operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(7))
      $0.integer(UInt16(144))
      if update { $0.integer(UInt64(1)) }
      $0.integer(enabled)
      if !update { $0.integer(UInt16(0)) }
    }
  }

  static var operations: [WireOperation] {
    [
      TreeFixture.create(1, kind: 140), section(2), TreeFixture.text(3, "Diagnostics"),
      TreeFixture.text(4, "Read only values"), TreeFixture.create(5, kind: 142),
      TreeFixture.text(6, "Revision"), selection(), TreeFixture.text(8, "abc123"),
      TreeFixture.create(9, kind: 143), TreeFixture.text(10, "No entries"),
      TreeFixture.text(11, "Create your first entry"),
      TreeFixture.button(12, role: 0, style: 0), TreeFixture.text(13, "Create entry"),
      section(14), TreeFixture.text(15, "Other"), TreeFixture.text(16, "Other footer"),
      TreeFixture.text(17, "Other row"),
      TreeFixture.children(7, [8]), TreeFixture.children(5, [6, 7]),
      TreeFixture.children(12, [13]), TreeFixture.children(9, [10, 11, 12]),
      TreeFixture.children(2, [3, 4, 5, 9]), TreeFixture.children(14, [15, 16, 17]),
      TreeFixture.children(1, [2, 14]), TreeFixture.root(1),
    ]
  }
}

@MainActor struct NativeFormTests {
  @Test func sectionStructureSurvivesTheTypeErasedRenderer() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(FormFixture.operations)).tree)
    var headers: [Int] = []
    var footers: [Int] = []
    var rows: [Int] = []
    let host = NSHostingView(
      rootView: Group(
        sections: ForEach(tree.root!.children) { node in
          NativeNodeView(node: node, activate: { _ in })
        }
      ) { sections in
        Color.clear.onAppear {
          headers = sections.map { $0.header.count }
          footers = sections.map { $0.footer.count }
          rows = sections.map { $0.content.count }
        }
      })
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 560, height: 700),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(headers == [1, 1])
    #expect(footers == [1, 1])
    #expect(rows == [2, 1])
  }

  @Test func nativeFormPreservesKeyedControlsAcrossReorderAndSelectionUpdates() throws {
    let store = try NodeStore().staging(TreeFixture.frame(FormFixture.operations)).tree
    let tree = RenderTree()
    tree.commit(store)
    let action = try #require(tree.nodes[12])
    let value = try #require(tree.nodes[8])
    tree.commit(
      try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.children(1, [14, 2]), FormFixture.selection(0, update: true),
            TreeFixture.text(8, "def456", update: true),
          ], base: 1, revision: 2)
      ).tree)
    #expect(tree.nodes[12] === action)
    #expect(tree.nodes[8] === value)
    #expect(value.properties == .text("def456"))
    #expect(tree.root?.children.map(\.id.node) == [14, 2])
    #expect(tree.nodes[7]?.properties != store.nodes[7]?.properties)
  }

  @Test func malformedNativeSlotsCannotPublish() throws {
    let store = try NodeStore().staging(TreeFixture.frame(FormFixture.operations)).tree
    for invalid in [
      TreeFixture.children(2, [3]), TreeFixture.children(5, [6]),
      TreeFixture.children(9, [10, 11]), TreeFixture.children(7, []),
      FormFixture.selection(2, update: true),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([invalid], base: 1, revision: 2))
      }
    }
    #expect(store.revision == 1)
  }

  @Test func hostedFormHasNativeSectionsSelectableValuesAndOrdinaryActions() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(FormFixture.operations)).tree)
    var activated: [UInt64] = []
    let host = NSHostingView(
      rootView: NativeNodeView(
        node: try #require(tree.root), activate: { activated.append($0.id.node) }))
    func leaf(_ id: UInt64) -> NativeNodeView {
      NativeNodeView(node: tree.nodes[id]!, activate: { _ in })
    }
    let reference = NSHostingView(
      rootView: Form {
        Section {
          LabeledContent {
            leaf(8).textSelection(.enabled)
          } label: {
            leaf(6)
          }
          ContentUnavailableView {
            leaf(10)
          } description: {
            leaf(11)
          } actions: {
            leaf(12)
          }
        } header: {
          leaf(3)
        } footer: {
          leaf(4)
        }
        Section {
          leaf(17)
        } header: {
          leaf(15)
        } footer: {
          leaf(16)
        }
      }.formStyle(.grouped))
    let windows = [host, reference].map { view in
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 560, height: 700),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = view
      window.orderFront(nil)
      return window
    }
    defer {
      for window in windows {
        window.orderOut(nil)
        window.contentView = nil
      }
    }
    try await settleAccessibility(host)
    try await settleAccessibility(reference)
    func signature(_ view: NSView) -> [String] {
      accessibilityElements(view).compactMap { element in
        guard let content = element.label ?? element.value, !content.isEmpty else { return nil }
        return "\(element.role ?? ""):\(content)"
      }.sorted()
    }
    #expect(signature(host) == signature(reference))
    func rect(_ label: String, in view: NSView) throws -> CGRect {
      let object = try #require(
        accessibilityElements(view).first {
          $0.label == label || $0.value == label
        }
      ).object
      let selector = NSSelectorFromString("accessibilityFrame")
      #expect(object.responds(to: selector))
      typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
      let frame = unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
      let origin = try #require(view.window).convertToScreen(view.bounds).origin
      return frame.offsetBy(dx: -origin.x, dy: -origin.y)
    }
    for label in [
      "Diagnostics", "Read only values", "Revision", "abc123", "No entries",
      "Create your first entry", "Create entry", "Other", "Other footer", "Other row",
    ] {
      let actual = try rect(label, in: host)
      let expected = try rect(label, in: reference)
      #expect(abs(actual.minX - expected.minX) <= 1, "\(label): \(actual) vs \(expected)")
      #expect(abs(actual.minY - expected.minY) <= 1, "\(label): \(actual) vs \(expected)")
      #expect(abs(actual.width - expected.width) <= 1)
      #expect(abs(actual.height - expected.height) <= 1)
    }
    let elements = accessibilityElements(host)
    let button = try #require(
      elements.first { $0.role == "AXButton" && $0.label == "Create entry" })
    #expect(button.press())
    #expect(activated == [12])
    #expect(!elements.contains { $0.role == "AXTextField" || $0.role == "AXTextArea" })
    func scrollViews(_ view: NSView) -> [NSScrollView] {
      (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
    #expect(scrollViews(host).count == 1)
    #expect(scrollViews(reference).count == 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeFormActionsReachOCamlAndRetainRowsDuringReordering() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-form")
      let root = try #require(session.tree.root)
      let action = try #require(session.tree.nodes.values.first { $0.kind == NodeKindId.button })
      let host = NSHostingView(
        rootView: NativeNodeView(node: root, activate: { _ = session.activate($0) }))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 560, height: 700),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      #expect(try await session.presented(#require(session.ticket)))
      let original = try #require(
        accessibilityElements(host).first {
          $0.role == "AXButton" && $0.label == "Create entry"
        })
      #expect(original.press())
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host)
      #expect(session.tree.nodes[action.id.node] === action)
      #expect(
        accessibilityElements(host).contains {
          $0.value == "Revision 1" || $0.label == "Revision 1"
        })
      let disabled = try #require(
        accessibilityElements(host).first {
          $0.role == "AXButton" && $0.label == "Create entry"
        })
      #expect(!disabled.enabled)
      _ = original.press()
      _ = disabled.press()
      _ = try await session.refresh()
      #expect(
        accessibilityElements(host).contains {
          $0.value == "Revision 1" || $0.label == "Revision 1"
        })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
