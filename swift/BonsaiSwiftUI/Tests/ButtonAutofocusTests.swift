import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor private func space(
  _ window: NSWindow, repeatKey: Bool = false, modifiers: NSEvent.ModifierFlags = []
) throws {
  for type in [NSEvent.EventType.keyDown, .keyUp] {
    window.sendEvent(
      try #require(
        NSEvent.keyEvent(
          with: type, location: .zero, modifierFlags: modifiers,
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, characters: " ", charactersIgnoringModifiers: " ",
          isARepeat: repeatKey && type == .keyDown, keyCode: 49)))
  }
}

@MainActor struct ButtonAutofocusTests {
  @Test func focusWaitsForPresentationActivatesSpaceOnceAndDoesNotStealEditingFocus() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.create(1), TreeFixture.button(2, autofocus: true),
          TreeFixture.text(3, "Action"),
          TreeFixture.editor(4, kind: 47, label: "Draft"),
          TreeFixture.children(2, [3]), TreeFixture.children(1, [2, 4]), TreeFixture.root(1),
        ])
      ).tree)
    let button = try #require(tree.nodes[2])
    let focus = try #require(button.focusController)
    let field = try #require(tree.nodes[4]?.fieldController?.field)
    tree.onInput = { _, _ in true }
    tree.nodes[4]?.fieldController?.setPresentationActive(true)
    var actions = 0
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root)) { node in
        #expect(node === button)
        actions += 1
      })
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 400, height: 160),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(!focus.hasFocus)
    #expect(window.makeFirstResponder(field))
    try await settleAccessibility(host)
    #expect(window.firstResponder === field.currentEditor())
    focus.setPresented(true)
    try await settleAccessibility(host)
    #expect(focus.hasFocus)
    #expect(!focus.wantsAutofocus)
    let draft = field.stringValue
    try space(window)
    try await settleAccessibility(host)
    #expect(actions == 1)
    #expect(field.stringValue == draft)
    try space(window, repeatKey: true)
    #expect(actions == 1)
    try space(window, modifiers: .command)
    #expect(actions == 1)
    #expect(focus.hasFocus)

    #expect(window.makeFirstResponder(field))
    try await settleAccessibility(host)
    let before = field.stringValue
    try space(window)
    try await settleAccessibility(host)
    #expect(actions == 1)
    #expect(field.stringValue != before)
    #expect(!focus.hasFocus)
    focus.setPresented(false)
    focus.setPresented(true)
    try await settleAccessibility(host)
    #expect(!focus.hasFocus)
    #expect(window.firstResponder === field.currentEditor())
    tree.commit(NodeStore())
    focus.setPresented(true)
    try space(window)
    #expect(actions == 1)
  }

  @Test func disabledFocusRequestRetriesWhenEnabledAndCannotActivateWhileInactive() async throws {
    initializeAccessibilityApplication()
    let store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.button(1, enabled: false, autofocus: true, handler: nil),
        TreeFixture.text(2, "Enable later"), TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree()
    tree.commit(store)
    let button = try #require(tree.root)
    let focus = try #require(button.focusController)
    var actions = 0
    let host = NSHostingView(rootView: NativeNodeView(node: button) { _ in actions += 1 })
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 140),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    focus.setPresented(true)
    try await settleAccessibility(host)
    #expect(!focus.hasFocus)
    try space(window)
    #expect(actions == 0)
    let update = TreeFixture.operation(OperationId.updateProps) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(NodeKindId.button))
      $0.integer(UInt64(15))
      $0.bytes.append(contentsOf: [1, 2, 3, 1])
    }
    let binding = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(1))
      $0.integer(UInt16(EventTagId.press))
      $0.integer(UInt64(9))
    }
    tree.commit(try store.staging(TreeFixture.frame([update, binding], base: 1, revision: 2)).tree)
    focus.setPresented(true)
    try await settleAccessibility(host)
    #expect(tree.root === button)
    #expect(focus.hasFocus)
    try space(window)
    #expect(actions == 1)
    focus.setPresented(false)
    try await settleAccessibility(host)
    try space(window)
    #expect(actions == 1)
    #expect(!focus.hasFocus)
    tree.commit(NodeStore())
    focus.setPresented(true)
    #expect(!focus.wantsAutofocus)
  }

  @Test func buttonFocusWireRejectsOldPayloadInvalidFlagsAndMalformedUpdates() throws {
    let valid = TreeFixture.button(1, autofocus: true)
    let store = try NodeStore().staging(
      TreeFixture.frame([
        valid, TreeFixture.text(2, "Focus"), TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    var old = valid.body
    old.remove(at: 13)
    var invalid = valid.body
    invalid[13] = 2
    for body in [old, invalid] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(
          TreeFixture.frame([
            WireOperation(opcode: OperationId.createNode, body: body),
            TreeFixture.text(2, "Focus"), TreeFixture.children(1, [2]), TreeFixture.root(1),
          ]))
      }
    }
    let update = TreeFixture.operation(OperationId.updateProps) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(NodeKindId.button))
      $0.integer(UInt64(15))
      $0.bytes.append(contentsOf: [1, 2, 3, 1])
    }
    for count in 0..<update.body.count {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [
              WireOperation(opcode: OperationId.updateProps, body: update.body.prefix(count))
            ], base: 1, revision: 2))
      }
    }
    #expect(store.revision == 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func buttonAutofocusRunsRealOCamlAndRetainsFocusAcrossHandlerReplacement()
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first { node in
          guard case .button = node.properties else { return false }
          return node.children.contains {
            if case .text(let value) = $0.properties { return value.value == title }
            return false
          }
        })
    }
    func count(_ value: Int) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == "Actions: \(value)" }
        return false
      }
    }
    func present() async throws {
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func flush() async throws {
      _ = try await session.refresh()
      try await present()
    }
    do {
      try await session.start(entrypoint: "native-button-focus")
      let target = try button("Focused action")
      let focus = try #require(target.focusController)
      let host = NSHostingView(
        rootView: NativeNodeView(node: try #require(session.tree.root)) { session.activate($0) })
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 420, height: 300),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      #expect(!focus.hasFocus)
      try await present()
      try await settleAccessibility(host)
      #expect(focus.hasFocus)
      try space(window)
      try await flush()
      try await settleAccessibility(host)
      #expect(count(1))
      #expect(try button("Focused action") === target)
      #expect(focus.hasFocus)
      try space(window, repeatKey: true)
      try await flush()
      #expect(count(1))
      let oldHandler = target.bindings[EventTagId.press]
      #expect(session.activate(try button("Replace handler")))
      _ = try await session.refresh()
      #expect(target.bindings[EventTagId.press] != oldHandler)
      #expect(!focus.hasFocus)
      try space(window)
      try await present()
      try await settleAccessibility(host)
      #expect(focus.hasFocus)
      try await flush()
      #expect(count(1))
      try space(window)
      try await flush()
      #expect(count(11))

      #expect(session.activate(try button("Toggle enabled")))
      try await flush()
      try await settleAccessibility(host)
      try space(window)
      try await flush()
      #expect(count(11))
      #expect(!focus.hasFocus)
      #expect(session.activate(try button("Toggle enabled")))
      try await flush()
      #expect(session.activate(try button("Toggle autofocus")))
      try await flush()
      #expect(session.activate(try button("Toggle autofocus")))
      _ = try await session.refresh()
      #expect(!focus.hasFocus)
      try await present()
      try await settleAccessibility(host)
      #expect(focus.hasFocus)
      try space(window)
      try await flush()
      #expect(count(21))
      session.isActive = false
      try space(window)
      session.isActive = true
      try await flush()
      #expect(count(21))
      #expect(session.activate(try button("Toggle visible")))
      try await flush()
      #expect(!focus.hasFocus)
      #expect(!session.activate(target))
      focus.setPresented(true)
      #expect(!focus.wantsAutofocus)
      #expect(session.activate(try button("Toggle visible")))
      try await flush()
      try await settleAccessibility(host)
      let replacement = try button("Focused action")
      #expect(replacement !== target)
      #expect(replacement.focusController?.hasFocus == true)
      try space(window)
      try await flush()
      #expect(count(31))
      await session.close()
      #expect(!session.activate(replacement))
      #expect(replacement.focusController?.hasFocus == false)
    } catch {
      await session.close()
      throw error
    }
  }
}
