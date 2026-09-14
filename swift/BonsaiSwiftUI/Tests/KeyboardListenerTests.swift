import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor private func sendKey(
  to window: NSWindow, code: UInt16 = 0, text: String = "a",
  action: NativeKey.Action = .down
) throws {
  let event = try #require(
    NSEvent.keyEvent(
      with: action == .up ? .keyUp : .keyDown, location: .zero,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil,
      characters: text, charactersIgnoringModifiers: text,
      isARepeat: action == .repeat, keyCode: code))
  NSApplication.shared.sendEvent(event)
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeKeyboardAutofocusWaitsForPresentationAndDoesNotStealFocus()
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-keyboard-autofocus")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 400, height: 120), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.makeKeyAndOrderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      #expect(window.makeFirstResponder(nil))
      try await settleAccessibility(host)
      try sendKey(to: window)
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host)
      try sendKey(to: window)
      try sendKey(to: window, action: .up)
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      let expected = "97:458756:down:0;97:458756:up:0;"
      func history() -> String? {
        session.tree.nodes.values.compactMap { node -> String? in
          if case .text(let text) = node.properties { return text.value }
          return nil
        }.first
      }
      #expect(history() == expected)
      #expect(window.makeFirstResponder(nil))
      try await settleAccessibility(host)
      session.isActive = false
      session.isActive = true
      try await settleAccessibility(host)
      try sendKey(to: window)
      try sendKey(to: window, action: .up)
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      #expect(history() == expected)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }

  @Test(arguments: [false, true]) @MainActor
  func nativeKeyboardListenersBubbleToOCamlAndRespectNativeEditing(handled: Bool) async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(
        entrypoint: handled ? "native-keyboard-handled" : "native-keyboard-ignored")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }
        ).modifier(NativeLayoutObserver(tree: session.tree)))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 400, height: 240), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.makeKeyAndOrderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      let fields = session.tree.nodes.values.compactMap { $0.fieldController?.field }.sorted {
        ($0.accessibilityLabel() ?? "") < ($1.accessibilityLabel() ?? "")
      }
      let first = try #require(fields.first)
      #expect(fields.count == 3)
      #expect(window.makeFirstResponder(first))
      try await settleAccessibility(host)
      try sendKey(to: window, code: 6, text: "z")
      #expect(try await session.presented(#require(session.ticket)))
      let editor = try #require(first.currentEditor() as? NSTextView)
      editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
      for action in [NativeKey.Action.down, .repeat, .repeat, .up] {
        try sendKey(to: window, action: action)
      }
      func history() throws -> String {
        try #require(
          session.tree.nodes.values.compactMap { node -> String? in
            guard case .text(let text) = node.properties, text.value.hasPrefix("Keys: ") else {
              return nil
            }
            return String(text.value.dropFirst(6))
          }.first)
      }
      func flush() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
        try await settleAccessibility(host)
      }
      try await flush()
      var expected = ["down", "repeat", "repeat", "up"].map { action in
        "inner:97:458756:\(action):0;" + (handled ? "" : "outer:97:458756:\(action):0;")
      }.joined()
      #expect(try history() == expected)
      #expect(editor.string == (handled ? "Draft" : "aaa"))
      for node in session.tree.nodes.values where node.fieldController != nil {
        #expect(try #require(node.layoutFrame).height > 0)
      }
      #expect(window.makeFirstResponder(fields[1]))
      try await settleAccessibility(host)
      try sendKey(to: window, code: 11, text: "b")
      try sendKey(to: window, code: 11, text: "b", action: .up)
      try await flush()
      expected += "outer:98:458757:down:0;outer:98:458757:up:0;"
      #expect(try history() == expected)
      #expect(window.makeFirstResponder(fields[2]))
      try await settleAccessibility(host)
      try sendKey(to: window)
      try sendKey(to: window, action: .up)
      try await flush()
      #expect(try history() == expected)
      #expect(window.makeFirstResponder(first))
      try await settleAccessibility(host)
      session.isVisible = false
      try sendKey(to: window)
      session.isVisible = true
      try sendKey(to: window, action: .repeat)
      try sendKey(to: window, action: .up)
      try await flush()
      #expect(try history() == expected)
      let other = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
        backing: .buffered, defer: false)
      other.contentView = NSTextField(string: "Other window")
      try sendKey(to: other)
      try await flush()
      #expect(try history() == expected)
      await session.close()
      try sendKey(to: window)
      try sendKey(to: window, action: .up)
    } catch {
      await session.close()
      throw error
    }
  }
}

extension TreeFixture {
  static func keyboardListener(
    _ id: UInt64 = 1, autofocus: UInt8 = 0, policy: UInt8 = 1,
    tags: [Int] = [EventTagId.key], update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(NodeKindId.keyboardListener))
      if update { $0.integer(UInt64(3)) }
      $0.integer(autofocus)
      $0.integer(policy)
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

@MainActor struct KeyboardListenerTests {
  @Test func rejectedListenersCannotAcquireAnInFlightSequence() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.keyboardListener(1), TreeFixture.keyboardListener(2),
          TreeFixture.editor(3, kind: 47), TreeFixture.children(2, [3]),
          TreeFixture.children(1, [2]), TreeFixture.root(1),
        ])
      ).tree)
    var admitted: Set<UInt64> = [1]
    var events: [String] = []
    tree.onInput = { node, event in
      guard case .key(let key) = event else { return true }
      guard admitted.contains(node.id.node) else { return false }
      events.append("\(node.id.node):\(key.action)")
      return true
    }
    let field = try #require(tree.nodes[3]?.fieldController?.field)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 360, height: 120),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer {
      tree.commit(NodeStore())
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(window.makeFirstResponder(field))
    try await settleAccessibility(host)
    for node in tree.nodes.values { node.keyboardController?.focus.setPresented(true) }
    try sendKey(to: window)
    #expect(events == ["1:down"])
    admitted = [1, 2]
    try sendKey(to: window, action: .repeat)
    try sendKey(to: window, action: .up)
    #expect(events == ["1:down", "1:repeat", "1:up"])
    admitted = []
    try sendKey(to: window)
    admitted = [1, 2]
    try sendKey(to: window, action: .repeat)
    try sendKey(to: window, action: .up)
    #expect(events == ["1:down", "1:repeat", "1:up"])
    try sendKey(to: window)
    admitted = [1]
    try sendKey(to: window, action: .repeat)
    admitted = [1, 2]
    try sendKey(to: window, action: .up)
    #expect(events == ["1:down", "1:repeat", "1:up", "2:down", "1:down", "1:repeat", "1:up"])
  }

  @Test func fieldEditorReuseAndBindingReplacementRetireHeldKeys() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.keyboardListener(), TreeFixture.create(2),
        TreeFixture.editor(3, kind: 47, label: "First"),
        TreeFixture.editor(4, kind: 47, label: "Second", session: 2),
        TreeFixture.children(2, [3, 4]), TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    tree.commit(store)
    var events: [(UInt64, NativeKey.Action)] = []
    tree.onInput = { node, event in
      if case .key(let key) = event, let handler = node.bindings[EventTagId.key] {
        events.append((handler, key.action))
      }
      return true
    }
    let controller = try #require(tree.root?.keyboardController)
    let first = try #require(tree.nodes[3]?.fieldController?.field)
    let second = try #require(tree.nodes[4]?.fieldController?.field)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 360, height: 180),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer {
      tree.commit(NodeStore())
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(window.makeFirstResponder(first))
    try await settleAccessibility(host)
    controller.focus.setPresented(true)
    try sendKey(to: window)
    #expect(events.count == 1 && events[0].1 == .down)
    let editor = try #require(first.currentEditor())
    #expect(window.makeFirstResponder(second))
    try await settleAccessibility(host)
    #expect(second.currentEditor() === editor)
    try sendKey(to: window, action: .repeat)
    try sendKey(to: window, action: .up)
    #expect(events.count == 1)
    try sendKey(to: window)
    #expect(events.count == 2)
    #expect(window.makeFirstResponder(nil))
    #expect(window.makeFirstResponder(second))
    try sendKey(to: window, action: .repeat)
    try sendKey(to: window, action: .up)
    #expect(events.count == 2)
    try sendKey(to: window)
    #expect(events.count == 3)
    let rebind = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(1))
      $0.integer(UInt16(EventTagId.key))
      $0.integer(UInt64(909))
    }
    store = try store.staging(TreeFixture.frame([rebind], base: 1, revision: 2)).tree
    tree.commit(store)
    try sendKey(to: window, action: .repeat)
    #expect(events.count == 3)
    controller.focus.setPresented(true)
    try sendKey(to: window, action: .up)
    #expect(events.count == 3)
    try sendKey(to: window)
    try sendKey(to: window, action: .up)
    #expect(events.map(\.0) == [109, 109, 109, 909, 909])
    #expect(events.map(\.1) == [.down, .down, .down, .down, .up])
    #expect(window.makeFirstResponder(nil))
    try sendKey(to: window)
    #expect(events.count == 5)
    tree.commit(NodeStore())
    controller.focus.setPresented(true)
    #expect(
      !controller.receive(NativeKey(logical: 97, physical: 0x70004, action: .down, modifiers: 0)))
    try sendKey(to: window)
    #expect(events.count == 5)
  }

  @Test func malformedKeyboardListenersRejectAtomically() throws {
    let operations = [
      TreeFixture.keyboardListener(), TreeFixture.text(2, "Target"),
      TreeFixture.children(1, [2]), TreeFixture.root(1),
    ]
    let store = try NodeStore().staging(TreeFixture.frame(operations)).tree
    let update = TreeFixture.keyboardListener(update: true)
    var invalid = [
      TreeFixture.keyboardListener(autofocus: 2, update: true),
      TreeFixture.keyboardListener(policy: 2, update: true), TreeFixture.children(1, []),
      TreeFixture.children(1, [2, 2]),
    ]
    for length in 0..<update.body.count {
      invalid.append(WireOperation(opcode: update.opcode, body: update.body.prefix(length)))
    }
    invalid.append(WireOperation(opcode: update.opcode, body: update.body + Data([0])))
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
    for tags in [[], [EventTagId.press], [EventTagId.key, EventTagId.press]] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(
          TreeFixture.frame([TreeFixture.keyboardListener(tags: tags)] + operations.dropFirst()))
      }
    }
    #expect(store.revision == 1)
  }
}
