import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor struct NavigationLinkRequestTests {
  private func emission(_ value: UInt8 = 1) -> NativeViewEmission {
    NativeViewEmission(
      instance: UUID(), generation: 1, kind: 2101, version: 1,
      event: 1, payload: Data([value]))
  }

  @Test func linkAdmissionWaitsForExactSettlementAndKeepsTheCommittedPath() throws {
    let controller = NavigationStackController()
    let event = emission()
    var admitted = 0
    let link = controller.linkValue(emission: event) {
      admitted += 1
      return true
    }
    #expect(
      controller.request(
        [link],
        emit: { _ in
          Issue.record("Unexpected pop")
          return false
        }))
    #expect(admitted == 1)
    #expect(controller.path.isEmpty)
    #expect(!controller.request([link], emit: { _ in true }))
    #expect(admitted == 1)
    controller.resolveLink(emission())
    #expect(!controller.request([link], emit: { _ in true }))
    controller.resolveLink(event)
    #expect(controller.request([link], emit: { _ in true }))
    #expect(admitted == 2)
  }

  @Test func deniedStaleForeignDisposedAndMalformedLinkRequestsDoNotNavigate() throws {
    let controller = NavigationStackController()
    let event = emission()
    var accepts = false
    var attempts = 0
    let link = controller.linkValue(emission: event) {
      attempts += 1
      return accepts
    }
    #expect(!controller.request([link], emit: { _ in true }))
    #expect(attempts == 1)
    accepts = true
    let foreign = NavigationStackController()
    #expect(!foreign.request([link], emit: { _ in true }))
    #expect(!controller.request([link, link], emit: { _ in true }))
    #expect(attempts == 1)
    #expect(controller.request([link], emit: { _ in true }))
    controller.resolveLink(event)
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(TreeFixture.navigationTree)).tree)
    controller.synchronize(try #require(tree.root).children)
    #expect(!controller.request(controller.path + [link], emit: { _ in true }))
    #expect(attempts == 2)
    let current = controller.linkValue(emission: event) {
      attempts += 1
      return true
    }
    controller.dispose()
    #expect(!controller.request([current], emit: { _ in true }))
    #expect(attempts == 2)
  }

  @Test func committedDestinationReplacesIntentAndNativeBackStillWorks() throws {
    let tree = RenderTree()
    let store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.navigationStack(), TreeFixture.text(2, "Root"),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    tree.commit(store)
    let controller = try #require(tree.root?.navigationController)
    let event = emission()
    let link = controller.linkValue(emission: event) { true }
    #expect(controller.request([link], emit: { _ in false }))
    tree.commit(
      try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.destination(3), TreeFixture.text(4, "Opened"),
            TreeFixture.children(3, [4]), TreeFixture.children(1, [2, 3]),
          ], base: 1, revision: 2)
      ).tree)
    controller.resolveLink(event)
    #expect(controller.path.count == 1)
    #expect(controller.destination(try #require(controller.path.first))?.id.node == 3)
    var payload: NativeEventPayload?
    #expect(
      controller.request(
        [],
        emit: {
          payload = $0
          return true
        }))
    #expect(payload == .navigationPath([]))
  }
}

@MainActor struct HostedNavigationLinkTests {
  @Test(arguments: [true, false])
  func registeredViewLinkOpensCommittedDestinationInTheExistingStack(admit: Bool) async throws {
    initializeAccessibilityApplication()
    var registry = BonsaiNativeViews()
    try registry.register(
      kind: 2101, version: 1, capabilities: [.semantics],
      decode: { _ in () },
      encodeEvent: { (event: String) in
        BonsaiNativeEvent(id: 1, payload: Data(event.utf8))
      }, makeResource: { () }, dispose: { _ in },
      content: { context in
        context.navigationLink(to: "open:block") { Text("Open block") }
      })
    let native = TreeFixture.operation(OperationId.createNode) {
      $0.integer(UInt64(2))
      $0.integer(UInt16(NodeKindId.nativeWidget))
      $0.integer(UInt32(2101))
      $0.integer(UInt16(1))
      $0.integer(UInt64(4))
      $0.integer(UInt32(0))
      $0.integer(UInt16(1))
      $0.integer(UInt16(EventTagId.nativeEvent))
      $0.integer(UInt64(91))
    }
    let store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.navigationStack(), native, TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree(nativeViews: registry)
    try tree.validate(store)
    tree.commit(store)
    var events = [NativeEventPayload]()
    var accepts = admit
    tree.onInput = { _, event in
      guard accepts else { return false }
      events.append(event)
      return true
    }
    let host = NSHostingController(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    host.sceneBridgingOptions = .all
    let window = NSWindow(contentViewController: host)
    window.setContentSize(NSSize(width: 420, height: 300))
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentViewController = nil
    }
    try await settleAccessibility(host.view)
    let instance = try #require(tree.nodes[2]?.nativeView)
    instance.canInteract = { true }
    instance.setPresented(true)
    try await settleAccessibility(host.view)
    let link = try #require(
      accessibilityElements(host.view).first {
        $0.label == "Open block" && ($0.role == "AXButton" || $0.role == "AXLink")
      })
    #expect(link.press())
    try await settleAccessibility(host.view)
    if !admit {
      #expect(events.isEmpty)
      let retry = try #require(
        accessibilityElements(host.view).first {
          $0.label == "Open block" && ($0.role == "AXButton" || $0.role == "AXLink")
        })
      accepts = true
      #expect(retry.press())
      try await settleAccessibility(host.view)
    }
    #expect(events.count == 1)
    guard case .nativeView(let event) = try #require(events.first) else {
      Issue.record("Link did not submit a native-view event")
      return
    }
    #expect(event.payload == Data("open:block".utf8))
    let controller = try #require(tree.root?.navigationController)
    #expect(controller.path.isEmpty)
    let next = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.destination(3), TreeFixture.text(4, "Opened block"),
          TreeFixture.children(3, [4]), TreeFixture.children(1, [2, 3]),
        ], base: 1, revision: 2)
    ).tree
    try tree.validate(next)
    tree.commit(next)
    controller.resolveLink(event)
    try await settleAccessibility(host.view)
    #expect(
      accessibilityElements(host.view).contains {
        $0.value == "Opened block" || $0.label == "Opened block"
      })
    #expect(controller.path.count == 1)
    #expect(controller.request([], emit: try #require(tree.root).emit))
    try await settleAccessibility(host.view)
    #expect(events.last == .navigationPath([]))
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeLinkSettlementAllowsRetryAndExpiresOldPresentation() async throws {
    initializeAccessibilityApplication()
    var registry = BonsaiNativeViews()
    var snapshots = [Int: BonsaiNativeContext<Int, String, Void>]()
    try registry.register(
      kind: 2101, version: 1, capabilities: [.semantics],
      decode: { Int(String(decoding: $0, as: UTF8.self))! },
      encodeEvent: { (event: String) in BonsaiNativeEvent(id: 1, payload: Data(event.utf8)) },
      makeResource: { () }, dispose: { _ in },
      content: { context in
        snapshots[context.properties] = context
        return context.navigationLink(to: "open") { Text("Open after \(context.properties)") }
      })
    let session = BonsaiSession(nativeViews: registry)
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-link")
      let root = try #require(session.tree.root)
      let controller = try #require(root.navigationController)
      let host = NSHostingController(
        rootView: NativeNodeView(node: root, activate: { session.activate($0) }))
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
      let old = try #require(snapshots[0]?.makeNavigationEvent("open"))
      // An ordinary native event with identical application bytes cannot settle a link.
      let held = controller.linkValue(emission: old.0) { true }
      #expect(controller.request([held], emit: { _ in false }))
      var ordinary = old.0
      ordinary.navigationRequest = nil
      controller.resolveLink(ordinary)
      #expect(!controller.request([held], emit: { _ in false }))
      controller.resolveLink(old.0)
      for count in 0..<2 {
        let link = try #require(
          accessibilityElements(host.view).first {
            $0.label == "Open after \(count)" && ($0.role == "AXButton" || $0.role == "AXLink")
          },
          "count=\(count), path=\(controller.path), labels=\(accessibilityElements(host.view).compactMap { $0.label ?? $0.value })"
        )
        #expect(link.press())
        try await settleAccessibility(host.view)
        #expect(try await session.refresh())
        #expect(!old.1())
        #expect(try await session.presented(#require(session.ticket)))
        try await settleAccessibility(host.view)
        #expect(controller.path.count == (count == 0 ? 0 : 1))
      }
      #expect(
        accessibilityElements(host.view).contains {
          $0.value == "Opened after two requests" || $0.label == "Opened after two requests"
        })
      #expect(controller.request([], emit: root.emit))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.path.isEmpty)
      await session.close()
      #expect(!old.1())
    } catch {
      await session.close()
      throw error
    }
  }
}
