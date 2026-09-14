import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func toggle(
    _ id: UInt64 = 1, value: UInt8 = 0, enabled: UInt8 = 1,
    style: UInt8 = 0, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(44))
      if update { $0.integer(UInt64(7)) }
      $0.integer(value)
      $0.integer(enabled)
      $0.integer(style)
      if !update {
        $0.integer(UInt16(enabled == 1 ? 1 : 0))
        if enabled == 1 {
          $0.integer(UInt16(EventTagId.valueChanged))
          $0.integer(UInt64(91))
        }
      }
    }
  }
  static func toggleTree(value: UInt8 = 0, enabled: UInt8 = 1, style: UInt8 = 0) -> [WireOperation]
  {
    [
      toggle(value: value, enabled: enabled, style: style), text(2, "Wi-Fi"), children(1, [2]),
      root(1),
    ]
  }
}

@MainActor struct ToggleTests {
  @Test func invalidPropertiesAndLabelOwnershipRejectAtomically() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.toggleTree())).tree
    for update in [
      TreeFixture.toggle(value: 2, update: true),
      TreeFixture.toggle(enabled: 2, update: true),
      TreeFixture.toggle(style: 4, update: true),
      TreeFixture.children(1, []),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([update], base: 1, revision: 2))
      }
    }
    let update = TreeFixture.toggle(value: 1, update: true)
    for count in 0..<update.body.count {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [
              WireOperation(
                opcode: update.opcode,
                body: update.body.prefix(count))
            ], base: 1, revision: 2))
      }
    }
    #expect(store.revision == 1)
  }

  @Test(arguments: [UInt8(0), 1, 2, 3], [true, false])
  func nativeToggleHasStateAndRespectsAdmission(style: UInt8, admit: Bool) async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(TreeFixture.frame(TreeFixture.toggleTree(style: style))).tree)
    var events: [NativeEventPayload] = []
    tree.onInput = { _, payload in
      events.append(payload)
      return admit
    }
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    func control() throws -> AccessibilityElement {
      return try #require(
        accessibilityElements(host).first { $0.label == "Wi-Fi" && $0.numericValue != nil })
    }
    #expect(try control().numericValue == 0)
    #expect(try control().press())
    try await settleAccessibility(host)
    #expect(events.count == 1)
    #expect(events.first?.tag == EventTagId.valueChanged)
    #expect(try control().numericValue == (admit ? 1 : 0))
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryTogglesAcceptRejectDisableAndRetainNativeState() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-toggle")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      let original = session.tree.nodes
      func element(_ title: String) throws -> AccessibilityElement {
        try #require(
          accessibilityElements(host).first {
            $0.label == title && ($0.role == "AXButton" || $0.numericValue != nil)
          })
      }
      func press(_ title: String) async throws {
        #expect(try element(title).press())
        if try await session.refresh() {
          #expect(try await session.presented(#require(session.ticket)))
        }
        try await settleAccessibility(host)
      }
      for title in ["Automatic", "Switch", "Checkbox", "Button"] {
        try await press(title)
        #expect(try element(title).numericValue == 1)
      }
      try await press("Ignore changes")
      for _ in 0..<2 {
        try await press("Checkbox")
        #expect(try element("Checkbox").numericValue == 1)
      }
      try await press("Accept changes")
      try await press("Checkbox")
      #expect(try element("Checkbox").numericValue == 0)
      try await press("Disable toggles")
      #expect(!(try element("Switch").enabled))
      _ = try element("Switch").press()
      #expect(!(try await session.refresh()))
      #expect(original.allSatisfy { session.tree.nodes[$0.key] === $0.value })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func toggleEchoPreservesFinalIntentAndRejectsDisabledStaleBindings() async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-toggle")
      #expect(try await session.presented(#require(session.ticket)))
      let node = try #require(
        session.tree.nodes.values.first {
          if case .booleanControl(let p) = $0.properties { return p.style == .toggle(2) }
          return false
        })
      let controller = try #require(node.booleanControlController)
      #expect(controller.request(true, emit: node.emit))
      #expect(try await session.refresh())
      #expect(controller.request(false, emit: node.emit))
      #expect(!(try await session.refresh()))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.value == false)
      guard case .booleanControl(let props) = node.properties else {
        Issue.record("Missing Toggle")
        return
      }
      #expect(!props.value)
      let stale = controller.binding(emit: node.emit)
      _ = stale.wrappedValue
      let disable = try #require(
        session.tree.nodes.values.first { node in
          guard case .button = node.properties, let child = node.children.first,
            case .text(let text) = child.properties
          else { return false }
          return text.value == "Disable toggles"
        })
      #expect(session.activate(disable))
      #expect(try await session.refresh())
      stale.wrappedValue = true
      #expect(controller.pending == nil)
      #expect(try await session.presented(#require(session.ticket)))
      #expect(!(try await session.refresh()))
      #expect(controller.value == false)
      await session.close()
      stale.wrappedValue = true
      #expect(controller.value == false)
    } catch {
      await session.close()
      throw error
    }
  }
}
