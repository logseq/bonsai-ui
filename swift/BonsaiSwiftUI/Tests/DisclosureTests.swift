import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func disclosure(
    _ id: UInt64 = 1, expanded: UInt8 = 0, enabled: UInt8 = 1,
    update: Bool = false, bound: Bool? = nil
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(133))
      if update { $0.integer(UInt64(3)) }
      $0.integer(expanded)
      $0.integer(enabled)
      if !update {
        let binding = bound ?? (enabled == 1)
        $0.integer(UInt16(binding ? 1 : 0))
        if binding {
          $0.integer(UInt16(EventTagId.valueChanged))
          $0.integer(UInt64(91))
        }
      }
    }
  }
  static func disclosureTree(_ node: WireOperation = disclosure()) -> [WireOperation] {
    [node, text(2, "Details"), text(3, "Body"), children(1, [2, 3]), root(1)]
  }
}

@MainActor struct DisclosureTests {
  @Test(arguments: [false, true])
  func matchesNativeDisclosurePresentation(expanded: Bool) throws {
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame(
          TreeFixture.disclosureTree(TreeFixture.disclosure(expanded: expanded ? 1 : 0)))
      ).tree)
    let actual = NativeNodeView(node: try #require(tree.root), activate: { _ in })
    let reference = DisclosureGroup(isExpanded: .constant(expanded)) {
      NativeTextView(text: "Body")
    } label: {
      NativeTextView(text: "Details")
    }
    #expect(try raster(actual).matches(raster(reference)))
  }

  @Test func malformedDisclosureCannotPartiallyPublish() throws {
    let original = try NodeStore().staging(TreeFixture.frame(TreeFixture.disclosureTree())).tree
    let change = TreeFixture.disclosure(expanded: 1, update: true)
    var invalid = [
      TreeFixture.disclosure(expanded: 2, update: true),
      TreeFixture.disclosure(enabled: 2, update: true), TreeFixture.children(1, [2]),
      TreeFixture.children(1, [2, 3, 2]),
    ]
    for count in 0..<change.body.count {
      invalid.append(WireOperation(opcode: change.opcode, body: change.body.prefix(count)))
    }
    invalid.append(WireOperation(opcode: change.opcode, body: change.body + Data([0, 0, 0])))
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
    for bad in [
      TreeFixture.disclosure(bound: false),
      TreeFixture.disclosure(enabled: 0, bound: true),
    ] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(TreeFixture.frame(TreeFixture.disclosureTree(bad)))
      }
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeDisclosureCollapseRevokesFocusBeforeTheNextPump() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-disclosure")
      #expect(try await session.presented(#require(session.ticket)))
      let owner = try #require(
        session.tree.nodes.values.first {
          $0.booleanControlController?.value == true
        })
      func button(in node: RenderNodeState) -> RenderNodeState? {
        if node.focusController != nil { return node }
        return node.children.lazy.compactMap { button(in: $0) }.first
      }
      let content = try #require(owner.children.last)
      let body = try #require(button(in: content))
      let focus = try #require(body.focusController)
      focus.setMounted(true)
      #expect(focus.isCollecting)
      let revision = session.displayedRevision
      let controller = try #require(owner.booleanControlController)
      #expect(controller.request(false, emit: owner.emit))
      #expect(session.displayedRevision == revision)
      #expect(!focus.isCollecting)
      #expect(!session.activate(body))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }

  @Test @MainActor func actualDisclosureOwnershipTracksExpansionAndPresentation() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func named(_ title: String, in node: RenderNodeState) -> Bool {
      if case .text(let text) = node.properties, text.value == title { return true }
      return node.children.contains { named(title, in: $0) }
    }
    func find(_ kind: Int, _ title: String) throws -> RenderNodeState {
      try #require(session.tree.nodes.values.first { $0.kind == kind && named(title, in: $0) })
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func press(_ title: String) async throws {
      #expect(session.activate(try find(NodeKindId.button, title)))
      try await flush()
    }
    do {
      try await session.start(entrypoint: "native-disclosure")
      let one = try find(133, "Item one")
      let two = try find(133, "Item two")
      let body = try find(NodeKindId.button, "Act in one")
      let hiddenBody = try find(NodeKindId.button, "Act in two")
      #expect(!one.emit(.valueChanged(false)))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(!session.activate(hiddenBody))
      #expect(!session.activate(try find(NodeKindId.button, "Header action")))
      #expect(!(try find(133, "Unavailable")).emit(.valueChanged(true)))
      #expect(two.emit(.valueChanged(true)))
      try await flush()
      #expect(named("Expanded: 1,2; actions: 0", in: try #require(session.tree.root)))
      try await press("Act in two")
      try await press("Single expansion")
      #expect(!session.activate(hiddenBody))
      #expect(two.emit(.valueChanged(true)))
      _ = try await session.refresh()
      #expect(!session.activate(body))
      #expect(!session.activate(hiddenBody))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(named("Expanded: 2; actions: 1", in: try #require(session.tree.root)))
      try await press("Multiple expansion")
      try await press("Single expansion")
      #expect(named("Expanded: 2; actions: 1", in: try #require(session.tree.root)))
      try await press("Reverse disclosures")
      #expect(try find(133, "Item one") === one)
      #expect(try find(NodeKindId.button, "Act in one") === body)
      try await press("Reject expansion")
      #expect(one.emit(.valueChanged(true)))
      try await flush()
      #expect(named("Expanded: 2; actions: 1", in: try #require(session.tree.root)))
      try await press("Disable disclosures")
      #expect(!two.emit(.valueChanged(false)))
      #expect(!session.activate(hiddenBody))
      await session.close()
      #expect(!one.emit(.valueChanged(true)))
    } catch {
      await session.close()
      throw error
    }
  }
}

extension DisclosureTests {
  @Test func nativeEditorRetainsDraftAndSelectionAcrossDisclosure() async throws {
    initializeAccessibilityApplication()
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.disclosure(expanded: 1), TreeFixture.text(2, "Editor details"),
        TreeFixture.editor(3), TreeFixture.children(1, [2, 3]),
        TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree()
    tree.onInput = { _, _ in true }
    tree.commit(store)
    let controller = try #require(tree.nodes[3]?.textController)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(window.makeFirstResponder(controller.view))
    controller.view.insertText("Local draft", replacementRange: NSRange(location: 0, length: 5))
    controller.view.setSelectedRange(NSRange(location: 2, length: 3))
    let selection = controller.session.value.selection
    for expanded in [false, true] {
      store = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.disclosure(expanded: expanded ? 1 : 0, update: true)
          ], base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
      try await settleAccessibility(host)
      #expect(controller.view.isEditable == expanded)
      if !expanded {
        #expect(window.firstResponder !== controller.view)
        controller.view.insertText(
          "Hidden edit", replacementRange: NSRange(location: 0, length: 11))
      } else {
        #expect(window.makeFirstResponder(controller.view))
      }
      #expect(controller.view.string == "Local draft")
      #expect(controller.session.value.selection == selection)
      #expect(tree.nodes[3]?.textController === controller)
    }
  }

}
