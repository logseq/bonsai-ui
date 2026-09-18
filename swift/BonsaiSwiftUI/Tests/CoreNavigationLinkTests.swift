import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor struct CoreNavigationLinkTests {
  @Test func orphanCoreLinkIsRejectedBeforePublishingTree() {
    let link = TreeFixture.operation(OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(NodeKindId.navigationLink))
      try! $0.string("entry")
      $0.integer(UInt8(1))
      $0.integer(UInt16(1))
      $0.integer(UInt16(EventTagId.press))
      $0.integer(UInt64(91))
    }
    #expect(throws: TreeError.invalidChildren) {
      try NodeStore().staging(
        TreeFixture.frame([
          link, TreeFixture.text(2, "Open"),
          TreeFixture.children(1, [2]), TreeFixture.root(1),
        ]))
    }
  }

  @Test func byteDistinctActivationReplacementReachesTheNativeOwner() throws {
    func link(_ activation: String, update: Bool = false) -> WireOperation {
      TreeFixture.operation(update ? OperationId.updateProps : OperationId.createNode) {
        $0.integer(UInt64(2))
        $0.integer(UInt16(NodeKindId.navigationLink))
        if update { $0.integer(UInt64(3)) }
        try! $0.string(activation)
        $0.integer(UInt8(1))
        if !update {
          $0.integer(UInt16(1))
          $0.integer(UInt16(EventTagId.press))
          $0.integer(UInt64(91))
        }
      }
    }
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.navigationStack(), link("é"), TreeFixture.text(3, "Open"),
        TreeFixture.children(2, [3]), TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree()
    tree.commit(initial)
    tree.commit(
      try initial.staging(TreeFixture.frame([link("e\u{301}", update: true)], base: 1, revision: 2))
        .tree)
    guard case .navigationLink(let properties) = tree.nodes[2]?.properties else {
      Issue.record("Missing link")
      return
    }
    #expect(Data(properties.activation.utf8) == Data("e\u{301}".utf8))
  }

  @Test func intentWaitsForReadinessAndSettlesOnlyItsExactEmission() async throws {
    let stack = NavigationStackController()
    var ready = false
    var emitted: [UUID] = []
    let value = stack.coreLinkValue(
      valid: { true }, ready: { ready },
      emit: {
        emitted.append($0)
        return true
      })
    #expect(stack.request([value], emit: { _ in false }))
    #expect(emitted.isEmpty && stack.path.isEmpty)
    ready = true
    stack.retryCoreLink()
    stack.retryCoreLink()
    #expect(emitted.count == 1)
    #expect(!stack.request([value], emit: { _ in false }))
    stack.resolveCoreLink(UUID())
    #expect(!stack.request([value], emit: { _ in false }))
    stack.resolveCoreLink(try #require(emitted.first))
    #expect(stack.request([value], emit: { _ in false }))
    #expect(emitted.count == 2 && stack.path.isEmpty)
  }

  @Test func replacementSupersedesOnlyUndeliveredIntentAndInvalidationCancels() {
    let stack = NavigationStackController()
    var ready = false
    var valid = true
    var emitted: [Int] = []
    let first = stack.coreLinkValue(
      valid: { true }, ready: { ready },
      emit: { _ in
        emitted.append(1)
        return true
      })
    let second = stack.coreLinkValue(
      valid: { valid }, ready: { ready },
      emit: { _ in
        emitted.append(2)
        return true
      })
    #expect(stack.request([first], emit: { _ in false }))
    #expect(stack.request([second], emit: { _ in false }))
    valid = false
    stack.retryCoreLink()
    valid = true
    ready = true
    stack.retryCoreLink()
    #expect(emitted.isEmpty)
    #expect(stack.request([second], emit: { _ in false }))
    #expect(emitted == [2])
    #expect(!stack.request([first], emit: { _ in false }))
    stack.dispose()
    #expect(!stack.request([second], emit: { _ in false }))
  }

  @Test func expiredAndForeignIntentsNeverEmit() async throws {
    let stack = NavigationStackController()
    var ready = false
    var count = 0
    let value = stack.coreLinkValue(
      valid: { true }, ready: { ready },
      emit: { _ in
        count += 1
        return true
      })
    #expect(!NavigationStackController().request([value], emit: { _ in false }))
    #expect(stack.request([value], emit: { _ in false }))
    try await Task.sleep(for: .milliseconds(550))
    ready = true
    stack.retryCoreLink()
    #expect(count == 0)
  }

  @Test func transportRejectionDoesNotReplayOnReadinessNotifications() {
    let stack = NavigationStackController()
    var count = 0
    let value = stack.coreLinkValue(
      valid: { true }, ready: { true },
      emit: { _ in
        count += 1
        return false
      })
    #expect(!stack.request([value], emit: { _ in false }))
    stack.retryCoreLink()
    #expect(count == 1)
    #expect(!stack.request([value], emit: { _ in false }))
    #expect(count == 2)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func coreLinkSurvivesRealPresentationGapAndReturnsToAnInteractiveRoot()
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "core-navigation-link")
      let root = try #require(session.tree.root)
      let stack = try #require(root.navigationController)
      let link = try #require(
        session.tree.nodes.values.first { $0.kind == NodeKindId.navigationLink })
      let originalHandler = link.bindings[EventTagId.press]
      let host = NSHostingController(rootView: NativeNodeView(node: root, activate: { _ in }))
      host.sceneBridgingOptions = .all
      let window = NSWindow(contentViewController: host)
      window.setContentSize(NSSize(width: 420, height: 300))
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentViewController = nil
      }
      try await settleAccessibility(host.view)
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host.view)
      let first = try #require(
        accessibilityElements(host.view).first {
          $0.label == "Core open 0" && ($0.role == "AXButton" || $0.role == "AXLink")
        })
      #expect(first.press())
      try await settleAccessibility(host.view)
      #expect(try await session.refresh())
      #expect(stack.path.isEmpty)
      #expect(link.bindings[EventTagId.press] == originalHandler)
      #expect(!link.coreLinkReady)
      try await settleAccessibility(host.view)
      let next = try #require(
        accessibilityElements(host.view).first {
          $0.label == "Core open 1" && ($0.role == "AXButton" || $0.role == "AXLink")
        })
      #expect(next.press())
      try await settleAccessibility(host.view)
      #expect(stack.path.isEmpty)
      #expect(try await session.presented(#require(session.ticket)))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(stack.path.count == 1)
      #expect(stack.request([], emit: root.emit))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host.view)
      #expect(session.tree.nodes[link.id.node] === link)
      let returned = try #require(
        accessibilityElements(host.view).first {
          $0.label == "Core open 0" && ($0.role == "AXButton" || $0.role == "AXLink")
        })
      #expect(returned.press())
      try await settleAccessibility(host.view)
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(stack.path.isEmpty)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
