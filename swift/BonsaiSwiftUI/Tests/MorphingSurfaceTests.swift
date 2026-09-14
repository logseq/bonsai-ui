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
      layoutFrame(3, width: 240, height: 140), text(4, "Compact content"),
      text(5, "Expanded content"), children(2, [4]), children(3, [5]),
      children(1, [2, 3]), root(1),
    ]
  }
}

@MainActor struct MorphingSurfaceTests {
  @Test func malformedTransitionsCannotPartiallyReplaceTheTree() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.morphTree())).tree
    for bad in [
      TreeFixture.morph(expanded: 2, update: true),
      TreeFixture.children(1, [2]), TreeFixture.children(1, [2, 3, 4]),
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
    #expect(store.accessibilityHiddenNodes == [3, 5])
    let expanded = try store.staging(TreeFixture.frame([change], base: 1, revision: 2)).tree
    #expect(expanded.accessibilityHiddenNodes == [2, 4])
  }

  @Test func nativeSurfaceRetainsBothBranchesAndOnlyExposesTheSelectedOne() async throws {
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
            TreeFixture.morph(expanded: expanded ? 1 : 0, update: true)
          ], base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
      try await settleAccessibility(host)
      let values = accessibilityElements(host).compactMap(\.value)
      #expect(values.contains(expanded ? "Expanded content" : "Compact content"))
      #expect(!values.contains(expanded ? "Compact content" : "Expanded content"))
      #expect(original.allSatisfy { tree.nodes[$0.key] === $0.value })
      #expect(abs(host.fittingSize.height - (expanded ? 152 : 40)) < 1)
    }
  }

  @Test func hiddenNativeEditorReleasesFocusAndRetainsDraftAndSelection() async throws {
    initializeAccessibilityApplication()
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.morph(expand: 0, collapse: 0), TreeFixture.editor(2),
        TreeFixture.text(3, "Expanded content"), TreeFixture.children(1, [2, 3]),
        TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree()
    tree.onInput = { _, _ in true }
    tree.commit(store)
    let controller = try #require(tree.nodes[2]?.textController)
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
    controller.view.insertText("Local draft", replacementRange: NSRange(location: 0, length: 5))
    controller.view.setSelectedRange(NSRange(location: 2, length: 3))
    let selection = controller.session.value.selection
    for expanded in [true, false] {
      store = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.morph(expanded: expanded ? 1 : 0, expand: 0, collapse: 0, update: true)
          ], base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
      try await settleAccessibility(host)
      #expect(controller.view.isEditable == !expanded)
      if expanded {
        #expect(window.firstResponder !== controller.view)
        controller.view.insertText(
          "Hidden edit", replacementRange: NSRange(location: 0, length: 11))
      } else {
        #expect(window.makeFirstResponder(controller.view))
      }
      #expect(controller.view.string == "Local draft")
      #expect(controller.session.value.selection == selection)
      #expect(tree.nodes[2]?.textController === controller)
    }
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
              expanded: expanded ? 1 : 0, expand: duration, collapse: duration, update: true)
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
      let compact = try button("Increment compact")
      let expanded = try button("Increment expanded")
      let toggle = try button("Toggle surface")
      for active in [compact, expanded, compact] {
        let hidden = active === compact ? expanded : compact
        #expect(!session.activate(hidden))
        #expect(session.activate(active))
        #expect(try await session.refresh())
        #expect(try await session.presented(#require(session.ticket)))
        #expect(session.activate(toggle))
        #expect(try await session.refresh())
        #expect(!session.activate(active))
        #expect(!session.activate(hidden))
        #expect(try await session.presented(#require(session.ticket)))
        #expect(session.tree.nodes[compact.id.node] === compact)
        #expect(session.tree.nodes[expanded.id.node] === expanded)
      }
      let texts = session.tree.nodes.values.compactMap { node -> String? in
        if case .text(let text) = node.properties { return text.value }
        return nil
      }
      #expect(texts.contains("Compact count: 2"))
      #expect(texts.contains("Expanded count: 1"))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension MorphingSurfaceTests {
  @Test(arguments: [1, 2, 3])
  func emptyBranchesRetainTheirLayoutSlots(emptyMask: Int) async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    var operations = [TreeFixture.morph(expand: 0, collapse: 0)]
    for (id, height, mask) in [(UInt64(2), 40.0, 1), (UInt64(3), 140.0, 2)] {
      if emptyMask & mask != 0 {
        operations.append(TreeFixture.create(id, kind: NodeKindId.empty))
      } else {
        operations += [
          TreeFixture.layoutFrame(id, width: 200, height: height),
          TreeFixture.text(id + 2, "Content"), TreeFixture.children(id, [id + 2]),
        ]
      }
    }
    operations += [TreeFixture.children(1, [2, 3]), TreeFixture.root(1)]
    var store = try NodeStore().staging(TreeFixture.frame(operations)).tree
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
      let expected =
        expanded ? (emptyMask & 2 != 0 ? 12.0 : 152.0) : (emptyMask & 1 != 0 ? 0.0 : 40.0)
      #expect(abs(host.fittingSize.height - expected) < 1)
    }
  }
}
