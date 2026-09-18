import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func morph(
    expanded: UInt8 = 0, expand: UInt32 = 240, collapse: UInt32 = 190,
    update: Bool = false, binding: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(41))
      if update { $0.integer(UInt64(7)) }
      $0.integer(expanded)
      $0.integer(expand)
      $0.integer(collapse)
      if !update {
        $0.integer(UInt16(binding ? 1 : 0))
        if binding {
          $0.integer(UInt16(1))
          $0.integer(UInt64(91))
        }
      }
    }
  }
  static func morphTree(_ surface: WireOperation = morph()) -> [WireOperation] {
    [
      surface, layoutFrame(2, width: 240, height: 40),
      text(4, "Shared content"), children(2, [4]), children(1, [2]), root(1),
    ]
  }
}

@MainActor struct MorphingSurfaceTests {
  @Test func singleActiveContentIsTheEntireSurfaceTree() throws {
    let store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.morph(), TreeFixture.text(2, "Active content"),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    #expect(store.nodes.count == 2)
    #expect(store.accessibilityHiddenNodes.isEmpty)
  }

  @Test func malformedTransitionsCannotPartiallyReplaceTheTree() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.morphTree())).tree
    for bad in [
      TreeFixture.morph(expanded: 2, update: true),
      TreeFixture.children(1, []), TreeFixture.children(1, [2, 4]),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([bad], base: 1, revision: 2))
      }
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame(TreeFixture.morphTree(TreeFixture.morph(binding: true))))
    }
    let change = TreeFixture.morph(expanded: 1, update: true)
    for length in 0..<change.body.count {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [
              WireOperation(opcode: change.opcode, body: change.body.prefix(length))
            ], base: 1, revision: 2))
      }
    }
    #expect(store.revision == 1)
    #expect(store.accessibilityHiddenNodes.isEmpty)
    let expanded = try store.staging(TreeFixture.frame([change], base: 1, revision: 2)).tree
    #expect(expanded.accessibilityHiddenNodes.isEmpty)
  }

  @Test func nativeSurfacePreservesSharedContentAcrossExtentChanges() async throws {
    initializeAccessibilityApplication()
    var store = try NodeStore().staging(TreeFixture.frame(TreeFixture.morphTree())).tree
    let tree = RenderTree()
    tree.commit(store)
    let original = tree.nodes
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in })
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    try #require(tree.root?.morphingSurfaceController).setReducedMotion(true)
    for expanded in [false, true, false] {
      store = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.morph(expanded: expanded ? 1 : 0, update: true),
            TreeFixture.layoutFrame(2, width: 240, height: expanded ? 140 : 40, update: true),
          ], base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
      try await settleAccessibility(host)
      let values = accessibilityElements(host).compactMap(\.value)
      #expect(values.contains("Shared content"))
      #expect(original.allSatisfy { tree.nodes[$0.key] === $0.value })
      #expect(abs(host.fittingSize.height - (expanded ? 152 : 40)) < 1)
    }
  }

  @Test func removedDetailEditorReleasesFocusAndCannotReceiveInput() async throws {
    initializeAccessibilityApplication()
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.morph(expanded: 1, expand: 0, collapse: 0), TreeFixture.create(2),
        TreeFixture.text(3, "Shared header"), TreeFixture.editor(4),
        TreeFixture.children(2, [3, 4]), TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree()
    tree.onInput = { _, _ in true }
    tree.commit(store)
    let shared = try #require(tree.nodes[3])
    let controller = try #require(tree.nodes[4]?.textController)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(window.makeFirstResponder(controller.view))
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.morph(expanded: 0, expand: 0, collapse: 0, update: true),
          TreeFixture.children(2, [3]),
          TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(4)) },
        ], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    #expect(tree.nodes[4] == nil)
    #expect(tree.nodes[3] === shared)
    #expect(!controller.view.isEditable)
    #expect(window.firstResponder !== controller.view)
    let text = controller.view.string
    controller.view.insertText("Stale input", replacementRange: NSRange(location: 0, length: 0))
    #expect(controller.view.string == text)
    try await settleAccessibility(host)
    #expect(!accessibilityElements(host).contains { $0.role == "AXTextArea" })
  }

  @Test func nativeAnimationInterpolatesAndReversesWithoutJumping() async throws {
    initializeAccessibilityApplication()
    var store = try NodeStore().staging(
      TreeFixture.frame(
        TreeFixture.morphTree(TreeFixture.morph(expand: 500, collapse: 500)))
    ).tree
    let tree = RenderTree()
    tree.commit(store)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in })
        .environment(\.scenePhase, .active))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    func change(_ expanded: Bool, duration: UInt32 = 500) throws {
      store = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.morph(
              expanded: expanded ? 1 : 0, expand: duration, collapse: duration, update: true),
            TreeFixture.layoutFrame(2, width: 240, height: expanded ? 140 : 40, update: true),
          ], base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
    }
    try change(true)
    try await settleAccessibility(host)
    let middle = host.fittingSize.height
    #expect(middle > 50 && middle < 150)
    let controller = try #require(tree.root?.morphingSurfaceController)
    let displayedProgress = controller.progress
    try change(false)
    #expect(controller.progress == displayedProgress)
    #expect(abs(host.fittingSize.height - middle) < 8)
    try await settleAccessibility(host)
    try await settleAccessibility(host)
    #expect(host.fittingSize.height < middle)
    try await Task.sleep(for: .milliseconds(450))
    try await settleAccessibility(host)
    #expect(abs(host.fittingSize.height - 40) < 1)
    try change(true, duration: 0)
    try await settleAccessibility(host)
    #expect(abs(host.fittingSize.height - 152) < 1)
    try change(false)
    try await Task.sleep(for: .milliseconds(70))
    host.rootView = NativeNodeView(node: try #require(tree.root), activate: { _ in })
      .environment(\.scenePhase, .background)
    try await settleAccessibility(host)
    #expect(abs(host.fittingSize.height - 40) < 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryMorphRejectsInactiveAndUnpresentedBranchInput() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-morph")
      #expect(try await session.presented(#require(session.ticket)))
      func button(_ label: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first { node in
            guard case .button = node.properties, let child = node.children.first,
              case .text(let text) = child.properties
            else { return false }
            return text.value == label
          })
      }
      let toggle = try button("Toggle surface")
      for expanded in [false, true, false] {
        let active = try button(expanded ? "Increment expanded" : "Increment compact")
        let previousID = active.id
        #expect(session.activate(active))
        #expect(try await session.refresh())
        #expect(try await session.presented(#require(session.ticket)))
        #expect(session.activate(toggle))
        #expect(try await session.refresh())
        #expect(!session.activate(active))
        let next = try button(expanded ? "Increment compact" : "Increment expanded")
        #expect(!session.activate(next))
        #expect(try await session.presented(#require(session.ticket)))
        #expect(
          session.tree.nodes[previousID.node] == nil
            || session.tree.nodes[previousID.node] !== active
            || active.bindings != next.bindings)
      }
      let texts = session.tree.nodes.values.compactMap { node -> String? in
        if case .text(let text) = node.properties { return text.value }
        return nil
      }
      #expect(texts.contains("Expanded count: 1"))
      #expect(!texts.contains("Compact count: 2"))
      #expect(session.activate(toggle))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let value) = $0.properties { return value.value == "Compact count: 2" }
          return false
        })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension MorphingSurfaceTests {
  @Test func emptyActiveContentHasOnlySurfaceInsets() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.morph(expand: 0, collapse: 0),
        TreeFixture.create(2, kind: NodeKindId.empty),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    tree.commit(store)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    for expanded in [false, true, false] {
      store = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.morph(expanded: expanded ? 1 : 0, expand: 0, collapse: 0, update: true)
          ], base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
      try await settleAccessibility(host)
      #expect(abs(host.fittingSize.height - (expanded ? 12 : 0)) < 1)
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualMailRetainsNativeRowsAndRemovesCollapsedDetails() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.borderless], backing: .buffered, defer: false)
    defer { window.contentView = nil }
    do {
      try await session.start(entrypoint: "mail-collection")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }
        )
        .environment(\.scenePhase, .active))
      window.contentView = host
      func settle(_ iterations: Int = 24) async throws {
        for _ in 0..<iterations {
          host.layoutSubtreeIfNeeded()
          if let ticket = session.ticket { _ = try await session.presented(ticket) }
          _ = try await session.refresh()
          try await Task.sleep(for: .milliseconds(15))
        }
      }
      func containsSender(_ node: RenderNodeState) -> Bool {
        if case .text(let value) = node.properties, value.value == "Mara Vale" { return true }
        return node.children.contains(where: containsSender)
      }
      func header() throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first {
            $0.kind == NodeKindId.button && containsSender($0)
          })
      }
      try await settle()
      let shared = try header()
      var row = shared
      while row.kind != NodeKindId.listRow {
        row = try #require(session.tree.parents[row.id.node].flatMap { session.tree.nodes[$0] })
      }
      func descendants(_ node: RenderNodeState) -> [RenderNodeState] {
        [node] + node.children.flatMap(descendants)
      }
      let initial = descendants(row).count
      for _ in 0..<3 {
        #expect(session.activate(try header()))
        try await settle(3)
        #expect(descendants(row).count > initial)
        #expect(try header() === shared)
        let surfaces = descendants(row).filter { $0.morphingSurfaceController != nil }
        #expect(!surfaces.isEmpty)
        #expect(surfaces.allSatisfy { $0.children.count == 1 })
        #expect(session.activate(try header()))
        try await settle()
        #expect(descendants(row).count == initial)
        #expect(session.tree.nodes[row.id.node] === row)
        #expect(try header() === shared)
      }
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
