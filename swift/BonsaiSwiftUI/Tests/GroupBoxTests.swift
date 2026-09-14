import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func groupBox(
    _ id: UInt64 = 1, labelled: UInt8 = 0, update: Bool = false, bound: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(106))
      if update { $0.integer(UInt64(1)) }
      $0.integer(labelled)
      if !update {
        $0.integer(UInt16(bound ? 1 : 0))
        if bound {
          $0.integer(UInt16(EventTagId.press))
          $0.integer(UInt64(91))
        }
      }
    }
  }
  static func groupBoxTree(labelled: Bool) -> [WireOperation] {
    [groupBox(labelled: labelled ? 1 : 0), text(2, "Body")]
      + (labelled ? [text(3, "Title")] : [])
      + [children(1, labelled ? [2, 3] : [2]), root(1)]
  }
}

@MainActor struct GroupBoxTests {
  @Test(arguments: [false, true], [false, true])
  func matchesNativeContainer(labelled: Bool, rtl: Bool) throws {
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(TreeFixture.frame(TreeFixture.groupBoxTree(labelled: labelled))).tree)
    let actual = NativeNodeView(node: try #require(tree.root), activate: { _ in })
    let reference: AnyView =
      labelled
      ? AnyView(
        GroupBox {
          Text("Body")
        } label: {
          Text("Title")
        })
      : AnyView(GroupBox { Text("Body") })
    #expect(
      try raster(actual, rtl ? .rightToLeft : .leftToRight).matches(
        raster(reference, rtl ? .rightToLeft : .leftToRight)))
  }

  @Test func invalidContainersCannotPartiallyPublish() throws {
    let original = try NodeStore().staging(
      TreeFixture.frame(TreeFixture.groupBoxTree(labelled: false))
    ).tree
    let change = TreeFixture.groupBox(labelled: 1, update: true)
    var invalid = [
      TreeFixture.groupBox(labelled: 2, update: true), change,
      TreeFixture.children(1, []), TreeFixture.children(1, [2, 2]),
    ]
    for count in 0..<change.body.count {
      invalid.append(WireOperation(opcode: change.opcode, body: change.body.prefix(count)))
    }
    invalid.append(
      WireOperation(opcode: change.opcode, body: change.body + Data(repeating: 0, count: 8)))
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try original.staging(
          TreeFixture.frame(
            [
              TreeFixture.text(2, "Must not leak", update: true), operation,
            ], base: 1, revision: 2))
      }
      #expect(original.revision == 1)
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.groupBox(bound: true), TreeFixture.text(2, "Body"),
          TreeFixture.children(1, [2]), TreeFixture.root(1),
        ]))
    }
  }

  @Test func changingLabelRetainsNativeEditorDraftAndSelection() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.groupBox(), TreeFixture.editor(2), TreeFixture.children(1, [2]),
        TreeFixture.root(1),
      ])
    ).tree
    tree.onInput = { _, _ in true }
    tree.commit(store)
    let editor = try #require(tree.nodes[2]?.textController)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(window.makeFirstResponder(editor.view))
    editor.view.insertText("Retained draft", replacementRange: NSRange(location: 0, length: 5))
    editor.view.setSelectedRange(NSRange(location: 2, length: 3))
    let selection = editor.session.value.selection
    for (labelled, labelID) in [(true, UInt64(3)), (false, UInt64(3)), (true, UInt64(4))] {
      var operations = [TreeFixture.groupBox(labelled: labelled ? 1 : 0, update: true)]
      if labelled {
        operations += [
          TreeFixture.text(labelID, "Editor group"), TreeFixture.children(1, [2, labelID]),
        ]
      } else {
        operations += [
          TreeFixture.children(1, [2]),
          TreeFixture.operation(OperationId.dropNode) { $0.integer(labelID) },
        ]
      }
      store = try store.staging(
        TreeFixture.frame(operations, base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
      try await settleAccessibility(host)
      #expect(tree.nodes[2]?.textController === editor)
      #expect(editor.view.string == "Retained draft")
      #expect(editor.session.value.selection == selection)
      #expect(editor.view.window === window)
      #expect(window.makeFirstResponder(editor.view))
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGroupedCardsRetainContentAndIndependentActions() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func named(_ title: String, in node: RenderNodeState) -> Bool {
      if case .text(let text) = node.properties, text.value == title { return true }
      return node.children.contains { named(title, in: $0) }
    }
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          if case .button = $0.properties { return named(title, in: $0) }
          return false
        })
    }
    func press(_ title: String) async throws {
      #expect(session.activate(try button(title)))
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    do {
      try await session.start(entrypoint: "native-groups")
      let body = try button("Act in one")
      #expect(!session.activate(body))
      #expect(try await session.presented(#require(session.ticket)))
      try await press("Select one")
      try await press("Act in one")
      #expect(named("Card: 1; actions: 1", in: try #require(session.tree.root)))
      try await press("Open two")
      #expect(named("Card: 2; actions: 1", in: try #require(session.tree.root)))
      try await press("Hide group label")
      #expect(try button("Act in one") === body)
      try await press("Reverse cards")
      #expect(try button("Act in one") === body)
      try await press("Show group label")
      try await press("Disable card actions")
      #expect(!session.activate(body))
      #expect(!session.activate(try button("Select one")))
      #expect(!session.activate(try button("Open two")))
      try await press("Enable card actions")
      try await press("Act in one")
      #expect(named("Card: 2; actions: 2", in: try #require(session.tree.root)))
      await session.close()
      #expect(!session.activate(body))
    } catch {
      await session.close()
      throw error
    }
  }
}
