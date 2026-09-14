import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func help(_ message: String, update: Bool = false, bound: Bool = false) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(63))
      if update { $0.integer(UInt64(1)) }
      try! $0.string(message)
      if !update {
        $0.integer(UInt16(bound ? 1 : 0))
        if bound {
          $0.integer(UInt16(EventTagId.press))
          $0.integer(UInt64(90))
        }
      }
    }
  }
  static func helpTree(_ message: String) -> [WireOperation] {
    [help(message), button(2), text(3, "Archive"), children(2, [3]), children(1, [2]), root(1)]
  }
}

@MainActor struct HelpTests {
  @Test func nativeHelpUpdatesWithoutReplacingOrSwallowingAction() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    var store = try NodeStore().staging(TreeFixture.frame(TreeFixture.helpTree("Move to archive")))
      .tree
    tree.commit(store)
    let button = try #require(tree.nodes[2])
    var actions = 0
    let host = NSHostingView(
      rootView: NativeNodeView(
        node: try #require(tree.root),
        activate: { node in
          if node === button { actions += 1 }
        }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 160), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    for (index, message) in ["Move to archive", "归档邮件 📬", "Keep this message for later"]
      .enumerated()
    {
      if index > 0 {
        store = try store.staging(
          TreeFixture.frame(
            [TreeFixture.help(message, update: true)], base: UInt64(index),
            revision: UInt64(index + 1))
        ).tree
        tree.commit(store)
      }
      try await settleAccessibility(host)
      #expect(tree.nodes[2] === button)
      let native = try #require(
        accessibilityElements(host).first { $0.role == "AXButton" && $0.label == "Archive" })
      #expect(native.help == message)
      _ = native.press()
      #expect(actions == index + 1)
    }
  }

  @Test func malformedHelpNeverPublishesPartialState() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.helpTree("Archive help")))
      .tree
    // The OCaml string contract trims ASCII whitespace, preserving other UTF-8.
    _ = try NodeStore().staging(TreeFixture.frame(TreeFixture.helpTree("\u{00A0}"))).tree
    let valid = TreeFixture.help("Updated", update: true)
    var invalid = [
      TreeFixture.help("", update: true), TreeFixture.help(" \n\t", update: true),
      TreeFixture.children(1, []), TreeFixture.children(1, [2, 3]),
    ]
    for count in 0..<valid.body.count {
      invalid.append(WireOperation(opcode: valid.opcode, body: valid.body.prefix(count)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [TreeFixture.text(3, "Must not publish", update: true), operation], base: 1, revision: 2
          ))
      }
      #expect(store.revision == 1)
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.help("Help", bound: true), TreeFixture.text(2, "Anchor"),
          TreeFixture.children(1, [2]), TreeFixture.root(1),
        ]))
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualHelpPreservesOCamlActionsAndNativeHints() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-help")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { node in _ = session.activate(node) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 240), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func button(_ title: String) throws -> AccessibilityElement {
        try #require(
          accessibilityElements(host).first { $0.role == "AXButton" && $0.label == title })
      }
      func flush() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
        try await settleAccessibility(host)
      }
      try await settleAccessibility(host)
      let archive = try button("Archive")
      _ = archive.press()
      _ = archive.press()
      try await flush()
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == "Help actions: 2" }
          return false
        })
      _ = try button("Change help").press()
      try await flush()
      #expect(try button("Archive").help == "归档邮件 📬")
      _ = try button("Disable action").press()
      try await flush()
      #expect(try !button("Archive").enabled)
      _ = archive.press()
      try await flush()
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == "Help actions: 2" }
          return false
        })
      _ = try button("Enable action").press()
      try await flush()
      _ = try button("Archive").press()
      try await flush()
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == "Help actions: 3" }
          return false
        })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
