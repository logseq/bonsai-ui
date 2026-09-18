import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor struct SwipeActionsTests {
  @Test func actionsRequireNativeRowsAndRejectMalformedStateAtomically() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.swipeTree())).tree
    for operation in [
      TreeFixture.swipe(enabled: 2, update: true),
      TreeFixture.swipeAction(title: "", update: true),
      TreeFixture.swipeAction(side: 2, update: true),
      TreeFixture.swipeAction(role: 3, update: true),
      TreeFixture.children(3, [2]), TreeFixture.children(12, [3]), TreeFixture.root(1),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
    #expect(store.revision == 1)
  }

  @Test func capturedActionCannotInvokeAReplacementHandler() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.swipeTree())).tree
    let tree = RenderTree()
    tree.commit(initial)
    let action = try #require(tree.nodes[3])
    let owner = try #require(tree.nodes[1]?.swipeController)
    guard case .swipeAction(let properties) = action.properties else { return }
    let captured = owner.generation
    var calls = 0
    tree.onInput = { _, _ in
      calls += 1
      return true
    }
    let rebind = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(3))
      $0.integer(UInt16(1))
      $0.integer(UInt16(1))
      $0.integer(UInt64(94))
    }
    tree.commit(try initial.staging(TreeFixture.frame([rebind], base: 1, revision: 2)).tree)
    #expect(!owner.perform(action, expected: properties, generation: captured))
    #expect(calls == 0)
    #expect(owner.perform(action, expected: properties, generation: owner.generation))
    #expect(calls == 1)
  }

  @Test func actionsAdmitOnceAndFenceRemovedDisabledAndChangedTargets() throws {
    let tree = RenderTree()
    var received: [RenderIdentity] = []
    var admit = false
    tree.onInput = { node, event in
      guard event == .press, admit else { return false }
      received.append(node.id)
      return true
    }
    var store = try NodeStore().staging(TreeFixture.frame(TreeFixture.swipeTree())).tree
    tree.commit(store)
    let owner = try #require(tree.nodes[1]?.swipeController)
    let action = try #require(tree.nodes[3])
    guard case .swipeAction(let original) = action.properties else {
      Issue.record("Missing action")
      return
    }
    #expect(!owner.perform(action, expected: original, generation: owner.generation))
    admit = true
    #expect(owner.perform(action, expected: original, generation: owner.generation))
    let request = try #require(owner.pending)
    #expect(!owner.perform(action, expected: original, generation: owner.generation))
    owner.resolve(request)
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.swipeAction(title: "Replacement", update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    #expect(!owner.perform(action, expected: original, generation: owner.generation))
    guard case .swipeAction(let updated) = action.properties else { return }
    #expect(owner.perform(action, expected: updated, generation: owner.generation))
    owner.resolve(request)
    #expect(owner.pending != nil)
    owner.resolve(try #require(owner.pending))
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.swipe(enabled: 0, update: true)
        ], base: 2, revision: 3)
    ).tree
    tree.commit(store)
    #expect(!owner.perform(action, expected: updated, generation: owner.generation))
    owner.dispose()
    #expect(!owner.perform(action, expected: updated, generation: owner.generation))
    #expect(received == [action.id, action.id])
  }
}
