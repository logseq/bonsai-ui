import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func outlineFrame() -> [WireOperation] {
    [
      systemList(), systemSection(2), text(3, "Header"), text(4, "Footer"),
      outlineRow(10, key: "parent", expanded: true), text(11, "Parent"),
      outlineRow(20, key: "sibling"), text(21, "Sibling"),
      outlineRow(30, key: "child"), text(31, "Child"),
      outlineRow(40, key: "branch", expanded: false), text(41, "Branch"),
      outlineRow(50, key: "child"), text(51, "Grandchild"),
      swipe(12), swipeAction(13, title: "Delete parent"), children(12, [13]),
      swipe(32), swipeAction(33, title: "Delete child"), children(32, [33]),
      children(2, [3, 4, 10, 20]), children(1, [2]), root(1),
    ]
      + rowSlots(10, label: 11, swipe: 12, descendants: [30, 40])
      + rowSlots(20, label: 21) + rowSlots(30, label: 31, swipe: 32)
      + rowSlots(40, label: 41, descendants: [50]) + rowSlots(50, label: 51)
  }
}

@MainActor struct NativeListHierarchyTests {
  @Test func explicitActionSlotsAndSiblingScopedNestedRowsAreAccepted() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.outlineFrame())).tree
    let tree = RenderTree()
    tree.commit(store)
    let parentActions = try #require(tree.nodes[12]?.swipeController)
    let childActions = try #require(tree.nodes[32]?.swipeController)
    #expect(parentActions.actions.map(\.id.node) == [13])
    #expect(childActions.actions.map(\.id.node) == [33])
    var activated: [UInt64] = []
    tree.onInput = { node, _ in
      activated.append(node.id.node)
      return true
    }
    let parent = try #require(tree.nodes[13])
    let child = try #require(tree.nodes[33])
    if case .swipeAction(let properties) = parent.properties {
      #expect(
        parentActions.perform(parent, expected: properties, generation: parentActions.generation))
    }
    if case .swipeAction(let properties) = child.properties {
      #expect(
        childActions.perform(child, expected: properties, generation: childActions.generation))
    }
    #expect(activated == [13, 33])
    let visibility = try #require(tree.root?.listVisibility)
    visibility.update(try #require(tree.nodes[40]?.id), visible: true)
    #expect(visibility.request == 2..<3)
    visibility.update(try #require(tree.nodes[50]?.id), visible: true)
    #expect(visibility.request == 2..<3)
    let collapsed = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.outlineRow(10, key: "parent", expanded: false, update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(collapsed)
    #expect(visibility.request == nil)
    #expect(tree.nodes[30]?.accessibilityHidden == true)
    #expect(tree.nodes[50]?.accessibilityHidden == true)
  }

  @Test func obsoleteWrapperGrammarAndInvalidRowSlotsAreRejected() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.outlineFrame())).tree
    for operation in [
      TreeFixture.children(10, [12]), TreeFixture.children(12, [11, 13]),
      TreeFixture.children(10, [100001, 32, 100003, 30, 40]),
      TreeFixture.children(20, [200001, 200002, 50]),
      TreeFixture.outlineRow(40, key: "child", expanded: false, update: true),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
  }
}

extension NativeListHierarchyTests {
  @Test func hostedDisclosureRowsRemainIndependentAndCollapsedRowsLeaveAccessibility() async throws
  {
    initializeAccessibilityApplication()
    var store = try NodeStore().staging(TreeFixture.frame(TreeFixture.outlineFrame())).tree
    let tree = RenderTree()
    tree.commit(store)
    let list = try #require(tree.root)
    let child = try #require(tree.nodes[30])
    let host = NSHostingView(rootView: NativeList(node: list, activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 500, height: 500),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      list.listScrollController?.dispose()
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    func tables(_ view: NSView) -> [NSTableView] {
      (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables)
    }
    let table = try #require(tables(host).first)
    #expect(table.numberOfRows == 6)
    func labels() -> [String] {
      (0..<table.numberOfRows).flatMap { row in
        table.view(atColumn: 0, row: row, makeIfNecessary: true).map(accessibilityElements) ?? []
      }.compactMap { $0.value ?? $0.label }
    }
    #expect(labels().contains("Parent"))
    #expect(labels().contains("Child"))
    #expect(!labels().contains("Grandchild"))
    let geometry = try #require(list.listScrollController?.nativeHost.geometry(child.id))
    let parentGeometry = try #require(
      list.listScrollController?.nativeHost.geometry(tree.nodes[10]!.id))
    #expect(geometry.row.minY >= parentGeometry.row.maxY)
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.outlineRow(10, key: "parent", expanded: false, update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    try await settleAccessibility(host)
    #expect(table.numberOfRows == 4)
    #expect(!labels().contains("Child"))
    #expect(tree.nodes[30] === child)
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.outlineRow(10, key: "parent", expanded: true, update: true),
          TreeFixture.outlineRow(40, key: "branch", expanded: true, update: true),
        ], base: 2, revision: 3)
    ).tree
    tree.commit(store)
    try await settleAccessibility(host)
    #expect(table.numberOfRows == 7)
    #expect(labels().contains("Grandchild"))
    #expect(tree.nodes[30] === child)
  }
}

extension NativeListHierarchyTests {
  @Test func reparentingCannotReuseNativeRowOrActionSlotIncarnations() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.outlineFrame())).tree
    for changes in [
      [
        TreeFixture.children(10, [100001, 12, 100003, 40]),
        TreeFixture.children(2, [3, 4, 10, 20, 30]),
      ],
      [
        TreeFixture.children(10, [100001, 32, 100003, 30, 40]),
        TreeFixture.children(30, [300001, 12, 300003]),
      ],
    ] {
      #expect(throws: TreeError.invalidIdentity) {
        try store.staging(TreeFixture.frame(changes, base: 1, revision: 2))
      }
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeOutlineSeparatesLabelExpansionAndActionOwnershipAcrossReparenting()
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-outline")
      #expect(try await session.presented(#require(session.ticket)))
      func texts(_ node: RenderNodeState) -> [String] {
        if case .text(let text) = node.properties { return [text.value] }
        return node.children.flatMap(texts)
      }
      func button(_ title: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first {
            $0.kind == NodeKindId.button && texts($0).contains(title)
          })
      }
      func row(_ title: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first {
            $0.kind == NodeKindId.listRow && $0.children.first.map(texts)?.contains(title) == true
          })
      }
      func flush() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      }
      func press(_ title: String) async throws {
        #expect(session.activate(try button(title)))
        try await flush()
      }
      let parent = try row("Open parent")
      let child = try row("Open child")
      let action = try #require(child.children[1].children.first)
      let owner = try #require(action.swipeActionOwner)
      guard case .swipeAction(let properties) = action.properties else {
        Issue.record("No action")
        return
      }
      let capturedGeneration = owner.generation
      let root = try #require(session.tree.root)
      let host = NSHostingView(
        rootView: NativeNodeView(node: root, activate: { _ = session.activate($0) }))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 650, height: 500), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      func elements(_ view: NSView) -> [AccessibilityElement] {
        if let table = view as? NSTableView {
          return (0..<table.numberOfRows).flatMap { row in
            table.view(atColumn: 0, row: row, makeIfNecessary: false).map(accessibilityElements)
              ?? []
          }
        }
        return accessibilityElements(view) + view.subviews.flatMap(elements)
      }
      let open = try #require(
        elements(host).first { $0.label == "Open parent" || $0.value == "Open parent" })
      #expect(open.press())
      try await flush()
      #expect(parent.booleanControlController?.value == true)
      try await settleAccessibility(host)
      #expect(elements(host).contains { $0.label == "Open child" })
      #expect(texts(root).contains("Actions 1 Open parent@0; scroll none"))
      #expect(owner.perform(action, expected: properties, generation: capturedGeneration))
      try await flush()
      #expect(texts(root).contains("Actions 2 Delete child@0; scroll none"))
      let parentOwner = try #require(parent.children[1].swipeController)
      let parentAction = try #require(parent.children[1].children.first)
      if case .swipeAction(let p) = parentAction.properties {
        #expect(parentOwner.perform(parentAction, expected: p, generation: parentOwner.generation))
        try await flush()
      }
      #expect(texts(root).contains("Actions 3 Delete parent@0; scroll none"))
      let expansion = try #require(parent.booleanControlController)
      func nativeDisclosureButton() throws -> NSButton {
        func outline(_ view: NSView) -> NSOutlineView? {
          (view as? NSOutlineView) ?? view.subviews.lazy.compactMap(outline).first
        }
        func buttons(_ view: NSView) -> [NSButton] {
          (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        let table = try #require(outline(host))
        let geometry = try #require(
          session.tree.listNodes.first?.listScrollController?.nativeHost.geometry(parent.id))
        let index = table.row(at: CGPoint(x: 1, y: geometry.row.midY))
        let row = try #require(table.rowView(atRow: index, makeIfNecessary: true))
        return try #require(buttons(row).first)
      }
      try nativeDisclosureButton().performClick(nil)
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
      #expect(!expansion.value)
      #expect(!owner.perform(action, expected: properties, generation: owner.generation))
      #expect(!session.activate(try button("Open child")))
      try await flush()
      try await settleAccessibility(host)
      #expect(child.accessibilityHidden)
      #expect(!elements(host).contains { $0.label == "Open child" })
      try nativeDisclosureButton().performClick(nil)
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
      #expect(expansion.value)
      try await settleAccessibility(host)
      #expect(!elements(host).contains { $0.label == "Open child" })
      #expect(!session.activate(try button("Open child")))
      try await flush()
      #expect(try row("Open child") === child)
      #expect(!owner.perform(action, expected: properties, generation: capturedGeneration))
      try await press("Rebind actions")
      #expect(!owner.perform(action, expected: properties, generation: capturedGeneration))
      #expect(owner.perform(action, expected: properties, generation: owner.generation))
      try await flush()
      #expect(texts(root).contains("Actions 4 Delete child@1; scroll none"))
      try await press("Move child")
      let moved = try row("Open child")
      #expect(moved.id != child.id)
      #expect(!owner.perform(action, expected: properties, generation: owner.generation))
      #expect(!session.activate(action))
      let movedOwner = try #require(moved.children[1].swipeController)
      let movedAction = try #require(moved.children[1].children.first)
      if case .swipeAction(let p) = movedAction.properties {
        #expect(movedOwner.perform(movedAction, expected: p, generation: movedOwner.generation))
        try await flush()
      }
      #expect(texts(root).contains("Actions 5 Delete child@1; scroll none"))
      try await press("Reject expansion")
      #expect(expansion.request(false, emit: parent.emit))
      try await flush()
      #expect(expansion.value)
      #expect(try row("Open parent") === parent)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }

  @Test @MainActor func nativeOutlineScrollReportsHiddenThenRevealsAnOffscreenDescendant()
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-outline")
      let root = try #require(session.tree.root)
      let host = NSHostingView(
        rootView: NativeNodeView(node: root, activate: { _ = session.activate($0) }))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 650, height: 400), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      #expect(try await session.presented(#require(session.ticket)))
      func contains(_ value: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value.contains(value) }
          return false
        }
      }
      for (buttonTitle, result) in [
        ("Target hidden", "scroll 1:hidden"), ("Reveal grandchild", "scroll 2:success"),
      ] {
        let button = try #require(
          session.tree.nodes.values.first {
            if $0.kind == NodeKindId.button, case .text(let text) = $0.children.first?.properties {
              return text.value == buttonTitle
            }
            return false
          })
        #expect(session.activate(button))
        let deadline = ContinuousClock.now + .seconds(3)
        while !contains(result) && ContinuousClock.now < deadline {
          _ = try await session.refresh()
          if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
          try await Task.sleep(for: .milliseconds(20))
        }
        #expect(contains(result))
      }
      let grandchild = try #require(
        session.tree.nodes.values.first {
          $0.kind == NodeKindId.listRow
            && $0.children.first?.children.first?.properties == .text("Grandchild")
        })
      let geometry = try #require(
        session.tree.listNodes.first?.listScrollController?.nativeHost.geometry(grandchild.id))
      #expect(geometry.aligned(anchor: 2))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NativeListHierarchyTests {
  @Test func labelActivationWinsInEitherNativeCallbackOrderAndDisposalRevokesPendingExpansion()
    async
  {
    func drain() async {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
    }
    for labelFirst in [false, true] {
      let interaction = ListRowInteraction()
      var expansions = 0
      if labelFirst { interaction.labelActivated() }
      interaction.expand { expansions += 1 }
      if !labelFirst { interaction.labelActivated() }
      await drain()
      #expect(expansions == 0)
      #expect(interaction.revision == 1)
      interaction.expand { expansions += 1 }
      await drain()
      #expect(expansions == 1)
      interaction.expand { expansions += 1 }
      interaction.dispose()
      await drain()
      #expect(expansions == 1)
    }
  }
}

extension NativeListHierarchyTests {
  @Test func rejectedOrRepeatedLinkActivationCannotFallThroughToRowExpansion() async {
    for admitted in [false, true] {
      let interaction = ListRowInteraction()
      let stack = NavigationStackController()
      let value = stack.coreLinkValue(
        valid: { admitted }, ready: { true },
        activated: { interaction.labelActivated() }, emit: { _ in true })
      let binding = stack.binding(emit: { _ in false })
      if admitted {
        binding.wrappedValue = [value]
        await withCheckedContinuation { continuation in
          DispatchQueue.main.async { continuation.resume() }
        }
      }
      var expansions = 0
      interaction.expand { expansions += 1 }
      binding.wrappedValue = [value]
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
      #expect(expansions == 0)
      #expect(stack.path.isEmpty)
      stack.dispose()
    }
  }
}

extension NativeListHierarchyTests {
  @Test func scrollingToAnExpandedParentUsesItsLabelRowInsteadOfItsSubtreeBounds() async throws {
    initializeAccessibilityApplication()
    var operations = TreeFixture.outlineFrame()
    operations[0] = ListScrollFixture.list(token: nil)
    operations += [
      TreeFixture.layoutFrame(101, height: 500), TreeFixture.children(101, [31]),
      TreeFixture.children(300001, [101]),
    ]
    var store = try NodeStore().staging(TreeFixture.frame(operations)).tree
    let tree = RenderTree()
    var result: ListScrollCompletion?
    tree.onInput = { _, payload in
      if case .listScrollCompleted(let completion) = payload {
        result = completion
        return true
      }
      return false
    }
    tree.commit(store)
    let list = try #require(tree.root)
    let parent = try #require(tree.nodes[10])
    let controller = try #require(list.listScrollController)
    let host = NSHostingView(rootView: NativeList(node: list, activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      controller.dispose()
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    store = try store.staging(
      TreeFixture.frame(
        [
          ListScrollFixture.list(token: 1, section: "2", path: ["parent"], anchor: 1, update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    controller.setPresentation(active: true, ready: true, acknowledgedToken: 1)
    let deadline = ContinuousClock.now + .seconds(3)
    while result == nil && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(result?.outcome == .succeeded)
    try await Task.sleep(for: .milliseconds(100))
    let geometry = try #require(controller.nativeHost.geometry(parent.id))
    #expect(geometry.row.height < 100)
    #expect(geometry.aligned(anchor: 1))
  }
}
