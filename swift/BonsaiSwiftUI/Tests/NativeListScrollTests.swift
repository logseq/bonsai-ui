import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

enum ListScrollFixture {
  static func list(
    token: Int64? = 1, section: String = "journal", path: [String] = ["entry"], anchor: UInt8 = 0,
    animated: UInt8 = 0, handler: UInt64? = 91, style: UInt8 = 0, update: Bool = false
  ) -> WireOperation {
    TreeFixture.operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(80))
      if update { $0.integer(UInt64(3)) }
      $0.integer(style)
      $0.integer(UInt8(token == nil ? 0 : 1))
      if let token {
        $0.integer(token)
        try! $0.string(section)
        $0.integer(UInt16(path.count))
        for key in path { try! $0.string(key) }
        $0.integer(anchor)
        $0.integer(animated)
      }
      if !update {
        $0.integer(UInt16(handler == nil ? 0 : 1))
        if let handler {
          $0.integer(UInt16(59))
          $0.integer(handler)
        }
      }
    }
  }

  static func section(_ id: UInt64 = 2, key: String = "journal") -> WireOperation {
    TreeFixture.operation(OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(81))
      $0.bytes += [0, 0, 0]
      try! $0.string(key)
      $0.integer(UInt16(0))
    }
  }

  static func row(_ id: UInt64, key: String) -> WireOperation {
    TreeFixture.outlineRow(id, key: key)
  }

  static func frame(token: Int64? = 1, path: [String] = ["entry"]) -> WireFrame {
    TreeFixture.frame(
      [
        list(token: token, path: path), section(), TreeFixture.create(3, kind: 1),
        TreeFixture.create(4, kind: 1), row(5, key: "entry"), TreeFixture.text(6, "Entry"),
        TreeFixture.children(2, [3, 4, 5]),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ] + TreeFixture.rowSlots(5, label: 6))
  }
}

@MainActor struct NativeListScrollTests {
  @Test func requestUpdatesRetainTheNativeListAndRejectTokenReuseWithChangedPayload() throws {
    let initial = try NodeStore().staging(ListScrollFixture.frame()).tree
    let tree = RenderTree()
    tree.commit(initial)
    let list = try #require(tree.root)
    for change in [
      ListScrollFixture.list(path: ["different"], update: true),
      ListScrollFixture.list(anchor: 1, update: true),
      ListScrollFixture.list(animated: 1, update: true),
    ] {
      #expect(throws: (any Error).self) {
        try initial.staging(TreeFixture.frame([change], base: 1, revision: 2))
      }
    }
    let next = try initial.staging(
      TreeFixture.frame(
        [
          ListScrollFixture.list(token: 2, update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(next)
    #expect(tree.root === list)
    let clear = try next.staging(
      TreeFixture.frame(
        [
          ListScrollFixture.list(token: nil, update: true)
        ], base: 2, revision: 3)
    ).tree
    #expect(throws: (any Error).self) {
      try clear.staging(
        TreeFixture.frame([ListScrollFixture.list(token: 1, update: true)], base: 3, revision: 4))
    }
    _ = try clear.staging(
      TreeFixture.frame([ListScrollFixture.list(token: 2, update: true)], base: 3, revision: 4))
  }

  @Test func requestTargetIdentityIsByteExact() throws {
    let initial = try NodeStore().staging(ListScrollFixture.frame(path: ["é"])).tree
    #expect(throws: (any Error).self) {
      try initial.staging(
        TreeFixture.frame(
          [
            ListScrollFixture.list(path: ["e\u{301}"], update: true)
          ], base: 1, revision: 2))
    }
  }

  @Test func malformedScrollRequestsFailBeforePublication() {
    for operation in [
      ListScrollFixture.list(token: 0), ListScrollFixture.list(token: -1),
      ListScrollFixture.list(path: []), ListScrollFixture.list(path: [""]),
      ListScrollFixture.list(anchor: 3), ListScrollFixture.list(animated: 2),
      ListScrollFixture.list(handler: nil),
    ] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(TreeFixture.frame([operation, TreeFixture.root(1)]))
      }
    }
  }
}

@MainActor struct ListScrollLifecycleTests {
  private let address = ListRowAddress(section: Data("journal".utf8), path: [Data("entry".utf8)])
  private let identity = RenderIdentity(epoch: 1, node: 5)
  private func request(_ token: Int64 = 1, anchor: Int = 0, animated: Bool = false)
    -> RenderListScrollRequest
  {
    .init(token: token, target: address, anchor: anchor, animated: animated)
  }

  @Test func offscreenMovementPrecedesRealizationAndRequiresStableAlignment() {
    var time = 0.0
    var movements: [RenderIdentity] = []
    var geometry: ListScrollGeometry?
    var results: [ListScrollCompletion] = []
    let controller = ListScrollController(automaticallySample: false, now: { time }) {
      results.append($0)
      return true
    }
    controller.synchronize(
      request(), handler: 91, rows: [address: .init(identity: identity, visible: true)])
    controller.attach(
      owner: UUID(), move: { id, _, _ in movements.append(id) }, geometry: { _ in geometry },
      stop: {})
    controller.setPresentation(active: true, ready: false, acknowledgedToken: nil)
    #expect(movements.isEmpty)
    controller.setPresentation(active: true, ready: true, acknowledgedToken: 1)
    #expect(movements == [identity])
    #expect(results.isEmpty)
    geometry = .init(
      row: CGRect(x: 0, y: 400, width: 300, height: 40),
      viewport: CGRect(x: 0, y: 360, width: 300, height: 200), minimumOffset: 0, maximumOffset: 800)
    controller.sample()
    #expect(results.isEmpty)
    geometry = .init(
      row: CGRect(x: 0, y: 400, width: 300, height: 40),
      viewport: CGRect(x: 0, y: 400, width: 300, height: 200), minimumOffset: 0, maximumOffset: 800)
    controller.sample()
    time = 0.010
    controller.sample()
    #expect(results.isEmpty)
    time = 0.017
    controller.sample()
    controller.sample()
    #expect(results == [.init(token: 1, handler: 91, outcome: .succeeded)])
    controller.synchronize(
      request(), handler: 92, rows: [address: .init(identity: identity, visible: true)])
    controller.setPresentation(active: true, ready: true, acknowledgedToken: 1)
    #expect(movements == [identity])
  }

  @Test func requestsSnapshotTargetsAndHandlersAndNeverReplayMotionForDelivery() {
    var results: [ListScrollCompletion] = []
    var accept = false
    var moves = 0
    var stops = 0
    let controller = ListScrollController(automaticallySample: false) {
      if accept { results.append($0) }
      return accept
    }
    let rows = [address: ListScrollTarget(identity: identity, visible: true)]
    controller.synchronize(request(), handler: 91, rows: rows)
    controller.attach(
      owner: UUID(), move: { _, _, _ in moves += 1 }, geometry: { _ in nil }, stop: { stops += 1 })
    controller.setPresentation(active: true, ready: true, acknowledgedToken: 1)
    controller.synchronize(request(), handler: 92, rows: rows)
    controller.synchronize(request(2), handler: 93, rows: rows)
    controller.setPresentation(active: true, ready: true, acknowledgedToken: 2)
    #expect(moves == 2)
    #expect(stops == 1)
    controller.synchronize(
      request(2), handler: 94,
      rows: [address: .init(identity: .init(epoch: 1, node: 10), visible: true)])
    #expect(stops == 2)
    accept = true
    controller.setPresentation(active: true, ready: true, acknowledgedToken: 2)
    controller.sample()
    #expect(
      results == [
        .init(token: 1, handler: 91, outcome: .superseded),
        .init(token: 2, handler: 93, outcome: .cancelled),
      ])
    #expect(moves == 2)
  }

  @Test func missingHiddenCancellationTimeoutAndDisposalHaveDistinctTerminals() {
    var time = 0.0
    var results: [ListScrollCompletion] = []
    let controller = ListScrollController(automaticallySample: false, now: { time }) {
      results.append($0)
      return true
    }
    let rows = [address: ListScrollTarget(identity: identity, visible: true)]
    controller.synchronize(request(), handler: 91, rows: [:])
    #expect(results.isEmpty)
    controller.setPresentation(active: true, ready: false, acknowledgedToken: 1)
    controller.synchronize(
      request(2), handler: 92, rows: [address: .init(identity: identity, visible: false)])
    controller.setPresentation(active: true, ready: false, acknowledgedToken: 2)
    controller.synchronize(request(3), handler: 93, rows: rows)
    controller.setPresentation(active: true, ready: false, acknowledgedToken: 3)
    time = 0.501
    controller.sample()
    controller.synchronize(request(4), handler: 94, rows: rows)
    controller.setPresentation(active: true, ready: false, acknowledgedToken: 4)
    controller.synchronize(nil, handler: nil, rows: rows)
    controller.synchronize(request(5), handler: 95, rows: rows)
    controller.setPresentation(active: false, ready: false, acknowledgedToken: 5)
    controller.synchronize(request(6), handler: 96, rows: rows)
    controller.setPresentation(active: true, ready: true, acknowledgedToken: 6)
    controller.attach(owner: UUID(), move: { _, _, _ in }, geometry: { _ in nil }, stop: {})
    time = 2.502
    controller.sample()
    #expect(
      results.map(\.outcome) == [
        .missingTarget, .hiddenTarget, .positioningFailed, .cancelled, .cancelled,
        .positioningFailed,
      ])
    controller.synchronize(request(7), handler: 97, rows: rows)
    controller.dispose()
    controller.setPresentation(active: true, ready: true, acknowledgedToken: 7)
    controller.sample()
    #expect(results.count == 6)
  }

  @Test func nativeGeometrySupportsLargeRowsAndBoundaryClamping() {
    let row = CGRect(x: 0, y: 100, width: 300, height: 500)
    #expect(
      ListScrollGeometry(
        row: row, viewport: CGRect(x: 0, y: 250, width: 300, height: 200), minimumOffset: 0,
        maximumOffset: 800
      ).aligned(anchor: 1))
    #expect(
      ListScrollGeometry(
        row: row, viewport: CGRect(x: 0, y: 400, width: 300, height: 200), minimumOffset: 0,
        maximumOffset: 800
      ).aligned(anchor: 2))
    #expect(
      ListScrollGeometry(
        row: CGRect(x: 0, y: 800, width: 300, height: 40),
        viewport: CGRect(x: 0, y: 640, width: 300, height: 200), minimumOffset: 0,
        maximumOffset: 640
      ).aligned(anchor: 0))
    #expect(
      !ListScrollGeometry(
        row: row, viewport: CGRect(x: 0, y: 300, width: 300, height: 200), minimumOffset: 0,
        maximumOffset: 800
      ).aligned(anchor: 0))
  }
}

@MainActor struct NativeListPositioningTests {
  @Test(arguments: [UInt8(0), UInt8(1)])
  func hostedListAlignsOffscreenRowsAndClampsBoundariesWithoutReplacingItsScrollView(style: UInt8)
    async throws
  {
    initializeAccessibilityApplication()
    var operations: [WireOperation] = [
      ListScrollFixture.list(token: nil, style: style), ListScrollFixture.section(),
      TreeFixture.create(3, kind: 1), TreeFixture.create(4, kind: 1),
    ]
    for index in 0..<100 {
      let row = UInt64(10 + index * 2)
      operations +=
        [
          ListScrollFixture.row(row, key: "entry\(index)"),
          TreeFixture.text(row + 1, "Entry \(index)"),
          TreeFixture.layoutFrame(
            UInt64(1000 + index), height: index == 50 ? 500 : (index.isMultiple(of: 2) ? 40 : 70)),
          TreeFixture.children(UInt64(1000 + index), [row + 1]),
        ] + TreeFixture.rowSlots(row, label: UInt64(1000 + index))
    }
    operations += [
      TreeFixture.children(2, [3, 4] + (0..<100).map { UInt64(10 + $0 * 2) }),
      TreeFixture.children(1, [2]), TreeFixture.root(1),
    ]
    var store = try NodeStore().staging(TreeFixture.frame(operations)).tree
    let tree = RenderTree()
    var results: [ListScrollCompletion] = []
    tree.onInput = { _, payload in
      if case .listScrollCompleted(let value) = payload {
        results.append(value)
        return true
      }
      return false
    }
    tree.commit(store)
    let node = try #require(tree.root)
    let controller = try #require(node.listScrollController)
    let host = NSHostingView(rootView: NativeList(node: node, activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      controller.dispose()
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    func scrollViews(_ view: NSView) -> [NSScrollView] {
      (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
    let scroll = try #require(scrollViews(host).first)
    #expect(controller.nativeHost.geometry(RenderIdentity(epoch: node.id.epoch, node: 170)) == nil)
    let cases: [(Int, UInt8)] = [
      (80, 0), (60, 1), (40, 2), (99, 0), (0, 2), (50, 1), (50, 2), (50, 0),
    ]
    for (offset, target) in cases.enumerated() {
      let token = Int64(offset + 1)
      store = try store.staging(
        TreeFixture.frame(
          [
            ListScrollFixture.list(
              token: token, path: ["entry\(target.0)"], anchor: target.1, style: style, update: true
            )
          ], base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
      controller.setPresentation(active: true, ready: true, acknowledgedToken: token)
      let deadline = ContinuousClock.now + .seconds(3)
      while results.last?.token != token && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
      }
      #expect(results.last == .init(token: token, handler: 91, outcome: .succeeded))
      #expect(scrollViews(host).first === scroll)
    }
    // Cancellation freezes the current native offset rather than returning to the origin.
    store = try store.staging(
      TreeFixture.frame(
        [
          ListScrollFixture.list(
            token: 9, path: ["entry99"], animated: 1, style: style, update: true)
        ], base: store.revision, revision: store.revision + 1)
    ).tree
    tree.commit(store)
    controller.setPresentation(active: true, ready: true, acknowledgedToken: 9)
    try await Task.sleep(for: .milliseconds(20))
    controller.userInteraction()
    let stopped = scroll.contentView.bounds.minY
    try await Task.sleep(for: .milliseconds(400))
    #expect(results.last == .init(token: 9, handler: 91, outcome: .cancelled))
    #expect(abs(scroll.contentView.bounds.minY - stopped) <= 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func listScrollCompletionUsesItsOriginalOCamlHandlerAfterSeveralRebindings()
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-list-scroll")
      #expect(try await session.presented(#require(session.ticket)))
      func button(_ title: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first {
            if $0.kind == NodeKindId.button, case .text(let text) = $0.children.first?.properties {
              return text.value == title
            }
            return false
          })
      }
      #expect(session.activate(try button("Move")))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      let list = try #require(session.tree.listNodes.first)
      let original = try #require(list.bindings[EventTagId.listScrollCompleted])
      for _ in 0..<3 {
        #expect(session.activate(try button("Rebind")))
        #expect(try await session.refresh())
        #expect(try await session.presented(#require(session.ticket)))
      }
      #expect(list.bindings[EventTagId.listScrollCompleted] != original)
      let root = try #require(session.tree.root)
      let host = NSHostingView(
        rootView: NativeNodeView(node: root, activate: { _ = session.activate($0) }))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 500, height: 400),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      let deadline = ContinuousClock.now + .seconds(3)
      var completed = false
      while !completed && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
        if try await session.refresh(), let ticket = session.ticket {
          #expect(try await session.presented(ticket))
        }
        completed = session.tree.nodes.values.contains {
          $0.properties == .text("Result 1 succeeded owner 0")
        }
      }
      #expect(completed)
      #expect(session.tree.listNodes.first === list)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension ListScrollLifecycleTests {
  @Test func reducedMotionAndEveryCancellationPathRetainOneOriginalTerminal() {
    for cancellation in 0..<4 {
      var moves: [Bool] = []
      var stops = 0
      var results: [ListScrollCompletion] = []
      let controller = ListScrollController(automaticallySample: false) {
        results.append($0)
        return true
      }
      let owner = UUID()
      let rows = [address: ListScrollTarget(identity: identity, visible: true)]
      controller.reducedMotion = true
      controller.attach(
        owner: owner, move: { _, _, animated in moves.append(animated) }, geometry: { _ in nil },
        stop: { stops += 1 })
      controller.synchronize(request(animated: true), handler: 91, rows: rows)
      controller.setPresentation(active: true, ready: true, acknowledgedToken: 1)
      switch cancellation {
      case 0: controller.userInteraction()
      case 1: controller.setPresentation(active: false, ready: false, acknowledgedToken: 1)
      case 2: controller.detach(owner: owner)
      default: controller.synchronize(nil, handler: nil, rows: rows)
      }
      controller.userInteraction()
      controller.sample()
      #expect(moves == [false])
      #expect(stops == 1)
      #expect(results == [.init(token: 1, handler: 91, outcome: .cancelled)])
      controller.synchronize(request(animated: true), handler: 92, rows: rows)
      controller.setPresentation(active: true, ready: true, acknowledgedToken: 1)
      #expect(moves.count == 1)
    }
  }
}
