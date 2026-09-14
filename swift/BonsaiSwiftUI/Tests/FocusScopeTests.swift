import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func focusScope(
    _ id: UInt64 = 1, autofocus: UInt8 = 0, update: Bool = false,
    tags: [Int] = [EventTagId.focusChanged]
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(NodeKindId.focusScope))
      if update { $0.integer(UInt64(1)) }
      $0.integer(autofocus)
      if !update {
        $0.integer(UInt16(tags.count))
        for tag in tags {
          $0.integer(UInt16(tag))
          $0.integer(UInt64(tag + 100))
        }
      }
    }
  }
}

@MainActor struct FocusScopeTests {
  @Test func changedAutofocusWaitsForTheNewPropertiesToBePresented() {
    let controller = FocusScopeController(autofocus: false, handler: 1, emit: { _ in true })
    controller.setMounted(true)
    controller.setPresented(true)
    controller.synchronize(autofocus: true, handler: 1)
    #expect(!controller.wantsAutofocus)
    #expect(controller.autofocusRequest == 0)
    controller.setPresented(true)
    #expect(controller.wantsAutofocus)
    #expect(controller.autofocusRequest == 1)
  }

  @Test func inactiveUnmountedReboundAndDisposedScopesDoNotPublishStaleFocus() {
    var events: [Bool] = []
    let controller = FocusScopeController(autofocus: false, handler: 1) { event in
      if case .focusChanged(let value) = event { events.append(value) }
      return true
    }
    controller.setMounted(true)
    controller.observeFocus(true)
    #expect(events.isEmpty)
    controller.setPresented(true)
    controller.observeFocus(true)
    #expect(events == [true])
    controller.setPresented(false)
    controller.observeFocus(false)
    #expect(events == [true])
    controller.setPresented(true)
    #expect(events == [true, false])
    controller.observeFocus(true)
    controller.setEnabled(false)
    #expect(events == [true, false, true, false])
    controller.observeFocus(false)
    controller.setEnabled(true)
    controller.observeFocus(true)
    controller.synchronize(autofocus: false, handler: 2)
    #expect(events.count == 5)
    controller.setPresented(true)
    #expect(events == [true, false, true, false, true, true])
    controller.setMounted(false)
    #expect(events.count == 6)
    controller.setMounted(true)
    #expect(events.last == false)
    controller.dispose()
    controller.setMounted(true)
    controller.setPresented(true)
    controller.observeFocus(true)
    #expect(events.count == 7)
  }

  @Test func autofocusWaitsForMountAndEnablementAndIsCancelledByProperties() {
    let controller = FocusScopeController(autofocus: true, handler: 1, emit: { _ in true })
    controller.setEnabled(false)
    controller.setPresented(true)
    controller.setMounted(true)
    #expect(!controller.wantsAutofocus)
    #expect(controller.autofocusRequest == 0)
    controller.setEnabled(true)
    #expect(controller.wantsAutofocus)
    #expect(controller.autofocusRequest == 1)
    controller.synchronize(autofocus: false, handler: 1)
    controller.setPresented(true)
    #expect(!controller.wantsAutofocus)
    #expect(controller.autofocusRequest == 1)
  }

  @Test func autofocusUsesNativeFocusAndDoesNotRepeatAfterFocusMovesAway() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.create(4), TreeFixture.focusScope(autofocus: 1),
          TreeFixture.text(2, "Focus target"), TreeFixture.editor(3, kind: 47, label: "Outside"),
          TreeFixture.children(1, [2]), TreeFixture.children(4, [1, 3]), TreeFixture.root(4),
        ])
      ).tree)
    var events: [Bool] = []
    tree.onInput = { node, event in
      if node.id.node == 1, case .focusChanged(let value) = event { events.append(value) }
      return true
    }
    let controller = try #require(tree.nodes[1]?.focusController)
    let field = try #require(tree.nodes[3]?.fieldController?.field)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 400, height: 180), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      tree.commit(NodeStore())
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(window.makeFirstResponder(field))
    try await settleAccessibility(host)
    #expect(events.isEmpty)
    #expect(field.currentEditor() != nil)
    controller.setPresented(true)
    try await settleAccessibility(host)
    #expect(events == [true])
    #expect(field.currentEditor() == nil)
    #expect(!controller.wantsAutofocus)
    #expect(window.makeFirstResponder(field))
    try await settleAccessibility(host)
    #expect(events == [true, false])
    controller.setPresented(false)
    controller.setPresented(true)
    try await settleAccessibility(host)
    #expect(events == [true, false])
    #expect(field.currentEditor() != nil)
  }

  @Test func invalidFocusScopeFramesRejectAtomically() throws {
    let operations = [
      TreeFixture.focusScope(), TreeFixture.text(2, "Target"),
      TreeFixture.children(1, [2]), TreeFixture.root(1),
    ]
    let store = try NodeStore().staging(TreeFixture.frame(operations)).tree
    let update = TreeFixture.focusScope(autofocus: 1, update: true)
    var invalid = [
      TreeFixture.focusScope(autofocus: 2, update: true), TreeFixture.children(1, []),
      TreeFixture.children(1, [2, 2]),
    ]
    for length in 0..<update.body.count {
      invalid.append(WireOperation(opcode: update.opcode, body: update.body.prefix(length)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
    for tags in [[], [EventTagId.press], [EventTagId.focusChanged, EventTagId.press]] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(
          TreeFixture.frame([TreeFixture.focusScope(tags: tags)] + operations.dropFirst()))
      }
    }
    #expect(store.revision == 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeFieldEditorsReportNestedScopeTransitionsToOCaml() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-focus-scope")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }
        ).modifier(NativeLayoutObserver(tree: session.tree)))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 400, height: 240), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      #expect(window.makeFirstResponder(nil))
      try await settleAccessibility(host)
      #expect(try await session.presented(#require(session.ticket)))
      let fields = session.tree.nodes.values.compactMap { $0.fieldController?.field }.sorted {
        ($0.accessibilityLabel() ?? "") < ($1.accessibilityLabel() ?? "")
      }
      #expect(fields.count == 3)
      for node in session.tree.nodes.values where node.fieldController != nil {
        let frame = try #require(node.layoutFrame)
        #expect(frame.width > 0 && frame.height > 0)
      }
      func history(_ title: String) -> String? {
        session.tree.nodes.values.compactMap { node -> String? in
          guard case .text(let text) = node.properties, text.value.hasPrefix(title) else {
            return nil
          }
          return String(text.value.dropFirst(title.count))
        }.first
      }
      func focus(_ field: NSTextField?, outer: String, inner: String) async throws {
        #expect(window.makeFirstResponder(field))
        try await settleAccessibility(host)
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
        #expect(history("Outer: ") == outer)
        #expect(history("Inner: ") == inner)
      }
      try await focus(try #require(fields.first), outer: "+", inner: "+")
      try await focus(fields[1], outer: "+", inner: "+")
      try await focus(fields[2], outer: "+", inner: "+-")
      try await focus(nil, outer: "+-", inner: "+-")
      session.isVisible = false
      try await focus(fields[0], outer: "+-", inner: "+-")
      session.isVisible = true
      try await focus(fields[0], outer: "+-+", inner: "+-+")
      session.isActive = false
      try await focus(nil, outer: "+-+", inner: "+-+")
      session.isActive = true
      try await focus(nil, outer: "+-+-", inner: "+-+-")
      let retired = session.tree.nodes.values.compactMap(\.focusController)
      await session.close()
      #expect(window.makeFirstResponder(fields[0]))
      for controller in retired {
        controller.setMounted(true)
        controller.setPresented(true)
        controller.observeFocus(true)
        #expect(!controller.isCollecting)
      }
    } catch {
      await session.close()
      throw error
    }
  }
}
