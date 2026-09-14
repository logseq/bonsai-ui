import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func toolbar(_ placements: [UInt8] = [3, 4], update: Bool = false) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(74))
      if update { $0.integer(UInt64(1)) }
      $0.integer(UInt16(placements.count))
      for placement in placements { $0.integer(placement) }
      if !update { $0.integer(UInt16(0)) }
    }
  }
  static func toolbarTree() -> [WireOperation] {
    [
      toolbar(), text(2, "Content"), text(3, "Primary"), text(4, "Secondary"),
      children(1, [2, 3, 4]), root(1),
    ]
  }
}

@MainActor struct ToolbarTests {
  @Test func toolbarPlacementChangesAndReorderingRetainContent() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.toolbarTree())).tree
    let tree = RenderTree()
    tree.commit(initial)
    let body = try #require(tree.nodes[2])
    let primary = try #require(tree.nodes[3])
    let updated = try initial.staging(
      TreeFixture.frame(
        [
          TreeFixture.toolbar([4, 3], update: true), TreeFixture.children(1, [2, 4, 3]),
        ], base: 1, revision: 2)
    ).tree
    tree.commit(updated)
    #expect(tree.nodes[2] === body)
    #expect(tree.nodes[3] === primary)
    #expect(tree.root?.children.map(\.id.node) == [2, 4, 3])
    let empty = try updated.staging(
      TreeFixture.frame(
        [
          TreeFixture.toolbar([], update: true), TreeFixture.children(1, [2]),
          TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(3)) },
          TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(4)) },
        ], base: 2, revision: 3)
    ).tree
    tree.commit(empty)
    #expect(tree.nodes[2] === body)
  }

  @Test func malformedToolbarUpdatesLeavePublishedTreeUntouched() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.toolbarTree())).tree
    for placements: [UInt8] in [[9], [1, 1], Array(repeating: 0, count: 257)] {
      #expect(throws: TreeError.invalidProperties) {
        _ = try initial.staging(
          TreeFixture.frame(
            [
              TreeFixture.toolbar(placements, update: true)
            ], base: 1, revision: 2))
      }
    }
    #expect(throws: TreeError.invalidChildren) {
      _ = try initial.staging(
        TreeFixture.frame(
          [
            TreeFixture.toolbar([3], update: true)
          ], base: 1, revision: 2))
    }
    let update = TreeFixture.toolbar(update: true)
    for length in 0..<update.body.count {
      let truncated = WireOperation(opcode: update.opcode, body: update.body.prefix(length))
      #expect(throws: (any Error).self) {
        _ = try initial.staging(TreeFixture.frame([truncated], base: 1, revision: 2))
      }
    }
    #expect(initial.nodes[1]?.children == [2, 3, 4])
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualToolbarRetainsCommandsAndRejectsStaleInput() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first { node in
          if case .button = node.properties {
            return node.children.contains { child in
              if case .text(let text) = child.properties { return text.value == title }
              return false
            }
          }
          return false
        })
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func text(_ value: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == value }
        return false
      }
    }
    do {
      try await session.start(entrypoint: "native-toolbar")
      #expect(try await session.presented(#require(session.ticket)))
      let command = try button("Toolbar action")
      #expect(session.activate(command))
      #expect(session.activate(command))
      try await flush()
      #expect(text("Toolbar actions: 2"))
      #expect(session.activate(try button("Reverse toolbar")))
      try await flush()
      #expect(try button("Toolbar action") === command)
      #expect(session.activate(try button("Move toolbar action")))
      _ = try await session.refresh()
      #expect(!session.activate(command))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.activate(command))
      try await flush()
      #expect(text("Toolbar actions: 3"))
      #expect(session.activate(try button("Disable toolbar action")))
      try await flush()
      #expect(!session.activate(command))
      #expect(session.activate(try button("Enable toolbar action")))
      try await flush()
      #expect(session.activate(try button("Hide toolbar")))
      try await flush()
      #expect(!session.activate(command))
      #expect(session.activate(try button("Show toolbar")))
      try await flush()
      let replacement = try button("Toolbar action")
      #expect(replacement !== command)
      #expect(!session.activate(command))
      #expect(session.activate(replacement))
      try await flush()
      #expect(text("Toolbar actions: 4"))
      let pin = try #require(session.tree.nodes.values.first { $0.booleanControlController != nil })
      #expect(try #require(pin.booleanControlController).request(true, emit: pin.emit))
      try await flush()
      #expect(text("Toolbar pinned"))
      let menu = try #require(session.tree.nodes.values.first { $0.menuController != nil })
      #expect(try #require(menu.menuController).select(-7, emit: menu.emit))
      #expect(!menu.menuController!.select(9, emit: menu.emit))
      try await flush()
      #expect(text("Toolbar actions: 5"))
      session.isVisible = false
      #expect(!session.activate(replacement))
      await session.close()
      #expect(!session.activate(replacement))
    } catch {
      await session.close()
      throw error
    }
  }
}
