import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func popover(
    presented: UInt8 = 0, edge: UInt8 = 0, update: Bool = false, bound: Bool = true
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(72))
      if update { $0.integer(UInt64(3)) }
      $0.integer(presented)
      $0.integer(edge)
      if !update {
        $0.integer(UInt16(bound ? 1 : 0))
        if bound {
          $0.integer(UInt16(EventTagId.valueChanged))
          $0.integer(UInt64(91))
        }
      }
    }
  }
  static func popoverTree(_ props: WireOperation = popover()) -> [WireOperation] {
    [
      props, text(2, "Anchor"), button(3), text(4, "Action"), children(3, [4]),
      children(1, [2, 3]), root(1),
    ]
  }
}

@MainActor struct PopoverTests {
  @Test func validatesPresentationAndRetainsClosedContent() throws {
    let original = try NodeStore().staging(TreeFixture.frame(TreeFixture.popoverTree())).tree
    #expect(original.accessibilityHiddenNodes.contains(3))
    let tree = RenderTree()
    tree.commit(original)
    let retained = try #require(tree.nodes[3])
    let shown = try original.staging(
      TreeFixture.frame(
        [TreeFixture.popover(presented: 1, edge: 4, update: true)], base: 1, revision: 2)
    ).tree
    tree.commit(shown)
    #expect(tree.nodes[3] === retained)
    #expect(!shown.accessibilityHiddenNodes.contains(3))
    var invalid = [
      TreeFixture.popover(presented: 2, update: true), TreeFixture.popover(edge: 5, update: true),
      TreeFixture.children(1, [2]), TreeFixture.children(1, [2, 3, 4]),
    ]
    let valid = TreeFixture.popover(update: true)
    for length in 0..<valid.body.count {
      invalid.append(WireOperation(opcode: valid.opcode, body: valid.body.prefix(length)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try original.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
      #expect(original.revision == 1)
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame(TreeFixture.popoverTree(TreeFixture.popover(bound: false))))
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualPopoverFencesContentAndRestoresRejectedNativeDismissal() async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-popover")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { _ = session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 350), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func contains(_ title: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        }
      }
      func button(_ title: String) throws -> RenderNodeState {
        let text = try #require(
          session.tree.nodes.values.first {
            if case .text(let text) = $0.properties { return text.value == title }
            return false
          })
        var node = text
        while true {
          if case .button = node.properties { return node }
          let child = node
          node = try #require(
            session.tree.nodes.values.first { $0.children.contains { $0 === child } })
        }
      }
      func nativeWindow() -> NSWindow? {
        NSApp.windows.first { candidate in
          candidate !== window && candidate.isVisible
            && candidate.contentView.map {
              accessibilityElements($0).contains {
                $0.role == "AXButton" && $0.label == "Keep message"
              }
            } == true
        }
      }
      func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<30 {
          _ = try await session.refresh()
          if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
          try await settleAccessibility(host)
          if condition() { return }
        }
        Issue.record("Popover did not settle")
        throw NSError(domain: "PopoverTests", code: 1)
      }
      let action = try button("Keep message")
      #expect(!session.activate(action))
      #expect(session.activate(try button("Show details")))
      try await settle { nativeWindow() != nil && contains("Details: Open") }
      let initial = try #require(nativeWindow()?.contentView)
      let nativeAction = try #require(
        accessibilityElements(initial).first { $0.role == "AXButton" && $0.label == "Keep message" }
      )
      _ = nativeAction.press()
      _ = nativeAction.press()
      try await settle { contains("Detail actions: 2") }
      #expect(session.activate(try button("Reject dismissal")))
      try await settle { contains("Accept dismissal") }
      try #require(nativeWindow()).cancelOperation(nil)
      try await settle { contains("Dismiss requests: 1") && nativeWindow() != nil }
      #expect(contains("Details: Open"))
      let owner = try #require(session.tree.nodes.values.first { $0.presentationController != nil })
      let controller = try #require(owner.presentationController)
      let obsolete = controller.binding(emit: owner.emit)
      _ = obsolete.wrappedValue
      #expect(!owner.emit(.valueChanged(true)))
      #expect(session.activate(try button("Replace dismissal handler")))
      try await settle { session.ticket == nil }
      _ = obsolete.wrappedValue
      obsolete.wrappedValue = false
      try await settle { nativeWindow() != nil }
      try #require(contains("Dismiss requests: 1"))
      session.isVisible = false
      for _ in 0..<5 { try await settleAccessibility(host) }
      #expect(nativeWindow() == nil)
      #expect(!session.activate(action))
      session.isVisible = true
      try await settle { nativeWindow() != nil }
      #expect(contains("Dismiss requests: 1"))
      #expect(session.activate(try button("Accept dismissal")))
      try await settle { contains("Reject dismissal") }
      try #require(nativeWindow()).cancelOperation(nil)
      try await settle { contains("Details: Closed") && nativeWindow() == nil }
      #expect(contains("Dismiss requests: 2"))
      #expect(!session.activate(action))
      #expect(session.activate(try button("Show details")))
      try await settle { nativeWindow() != nil }
      #expect(try button("Keep message") === action)
      #expect(session.activate(try button("Close details")))
      try await settle { nativeWindow() == nil && contains("Details: Closed") }
      #expect(contains("Dismiss requests: 2"))
      #expect(session.activate(try button("Show details")))
      try await settle { nativeWindow() != nil }
      await session.close()
      for _ in 0..<5 { try await settleAccessibility(host) }
      #expect(nativeWindow() == nil)
      #expect(!session.activate(action))
    } catch {
      await session.close()
      throw error
    }
  }
}
