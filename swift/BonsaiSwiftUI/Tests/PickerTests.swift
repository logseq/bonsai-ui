import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryPickerPreservesIdentityAndControlledSelection() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func text(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          if case .text(let value) = $0.properties { return value.value == title }
          return false
        })
    }
    func button(_ title: String) throws -> RenderNodeState {
      let label = try text(title)
      return try #require(session.tree.nodes.values.first { $0.children.contains { $0 === label } })
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    do {
      try await session.start(entrypoint: "native-picker")
      #expect(try await session.presented(#require(session.ticket)))
      let pickers = session.tree.nodes.values.filter {
        if case .picker(let properties) = $0.properties {
          return ["Automatic", "Menu", "Segmented", "Inline"].contains(properties.label)
        }
        return false
      }.sorted {
        $0.id.node < $1.id.node
      }
      #expect(pickers.count == 4)
      let independent = try #require(
        session.tree.nodes.values.first {
          if case .picker(let properties) = $0.properties {
            return properties.label == "Single choice"
          }
          return false
        })
      #expect(independent.pickerController?.selection == -7)
      for (index, node) in pickers.enumerated() {
        #expect(
          try #require(node.pickerController).request(
            index.isMultiple(of: 2) ? 2 : -1, emit: node.emit))
        try await flush()
      }
      let node = try #require(pickers.first)
      let controller = try #require(node.pickerController)
      #expect(session.activate(try button("Ignore picker changes")))
      try await flush()
      for _ in 0..<2 {
        #expect(controller.request(2, emit: node.emit))
        #expect(!(try await session.refresh()))
        #expect(controller.selection == -1)
      }
      #expect(session.activate(try button("Accept picker changes")))
      try await flush()
      #expect(controller.request(2, emit: node.emit))
      #expect(try await session.refresh())
      let pending = try #require(session.ticket)
      #expect(controller.request(-1, emit: node.emit))
      #expect(try await session.presented(pending))
      try await flush()
      #expect(controller.selection == -1)

      let firstLabels = pickers.map { $0.children[0] }
      let oldBinding = controller.binding(emit: node.emit)
      #expect(session.activate(try button("Reverse picker options")))
      try await flush()
      oldBinding.wrappedValue = 2
      #expect(!(try await session.refresh()))
      for (picker, label) in zip(pickers, firstLabels) {
        #expect(picker.children.last === label)
      }
      #expect(session.activate(try button("Disable pickers")))
      try await flush()
      #expect(!controller.request(2, emit: node.emit))
      #expect(!node.emit(.pickerSelection(2)))
      #expect(session.activate(try button("Enable pickers")))
      try await flush()
      #expect(session.activate(try button("Clear picker selection")))
      try await flush()
      #expect(pickers.allSatisfy { $0.pickerController?.selection == nil })
      #expect(independent.pickerController?.selection == -7)
      await session.close()
      #expect(!controller.request(2, emit: node.emit))
    } catch {
      await session.close()
      throw error
    }
  }
}

extension TreeFixture {
  static func picker(
    selected: Int64? = -1, style: UInt8 = 3, enabled: UInt8 = 1,
    ids: [Int64] = [-1, 2, 3], update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(116))
      if update { $0.integer(UInt64(31)) }
      $0.integer(UInt8(selected == nil ? 0 : 1))
      if let selected { $0.integer(selected) }
      $0.integer(UInt16(ids.count))
      for id in ids {
        $0.integer(id)
        $0.integer(UInt8(id == 3 ? 0 : 1))
        $0.integer(UInt8(1))
      }
      try! $0.string("Layout")
      $0.integer(style)
      $0.integer(enabled)
      if !update {
        $0.integer(UInt16(enabled == 1 ? 1 : 0))
        if enabled == 1 {
          $0.integer(UInt16(53))
          $0.integer(UInt64(91))
        }
      }
    }
  }
  static func pickerTree(style: UInt8 = 3, selected: Int64? = -1, enabled: UInt8 = 1)
    -> [WireOperation]
  {
    [
      picker(selected: selected, style: style, enabled: enabled), text(2, "First"),
      text(3, "Second"), text(4, "Disabled"), children(1, [2, 3, 4]), root(1),
    ]
  }
}

@MainActor struct PickerTests {
  @Test(arguments: [UInt8(0), 1])
  func nativePopupMenuHonorsDisabledItemsAndDispatchesThroughItsTarget(style: UInt8) async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(TreeFixture.frame(TreeFixture.pickerTree(style: style))).tree)
    var events: [NativeEventPayload] = []
    tree.onInput = { _, payload in
      events.append(payload)
      return true
    }
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    var views = [host as NSView]
    var popup: NSPopUpButton?
    while let view = views.popLast() {
      if let value = view as? NSPopUpButton {
        popup = value
        break
      }
      views.append(contentsOf: view.subviews)
    }
    let control = try #require(popup)
    let disabled = try #require(control.itemArray.first { $0.title == "Disabled" })
    #expect(!disabled.isEnabled)
    control.selectItem(withTitle: "Second")
    #expect(control.sendAction(control.action, to: control.target))
    try await settleAccessibility(host)
    #expect(events == [.pickerSelection(2)])
    #expect(control.selectedItem?.title == "Second")
    control.select(disabled)
    _ = control.sendAction(control.action, to: control.target)
    try await settleAccessibility(host)
    #expect(events.count == 1)
    #expect(control.selectedItem?.title == "Second")
  }

  @Test func queuedChoicesCoalesceAndReorderedOptionsInvalidateOldBindings() throws {
    let tree = RenderTree()
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.pickerTree())).tree
    tree.commit(initial)
    let root = try #require(tree.root)
    let controller = try #require(root.pickerController)
    var queue = NativeEventQueue(maximumCount: 1)
    var sequence: UInt64 = 0
    tree.onInput = { _, payload in
      sequence += 1
      return queue.append(
        NativeEvent(
          sequence: sequence, displayedRevision: 1,
          nodeID: 1, handlerID: 91, payload: payload))
    }
    #expect(controller.request(2, emit: root.emit))
    let first = try #require(controller.pending)
    #expect(controller.request(-1, emit: root.emit))
    #expect(queue.events.count == 1)
    #expect(queue.events.first?.payload == .pickerSelection(-1))
    controller.resolve(first)
    #expect(controller.pending != nil)
    let stale = controller.binding(emit: root.emit)
    tree.commit(
      try initial.staging(
        TreeFixture.frame(
          [
            TreeFixture.picker(selected: 2, ids: [2, -1, 3], update: true)
          ], base: 1, revision: 2)
      ).tree)
    #expect(controller.selection == 2)
    let before = sequence
    stale.wrappedValue = -1
    #expect(sequence == before)
    #expect(!controller.request(3, emit: root.emit))
    #expect(!controller.request(99, emit: root.emit))
    let fresh = controller.binding(emit: root.emit)
    fresh.wrappedValue = -1
    #expect(controller.selection == -1)
    controller.dispose()
    fresh.wrappedValue = 2
    #expect(controller.selection == -1)
  }

  @Test func malformedSelectionOptionsAndOwnershipRejectAtomically() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.pickerTree())).tree
    for operation in [
      TreeFixture.picker(selected: 9, update: true),
      TreeFixture.picker(style: 4, update: true),
      TreeFixture.picker(enabled: 2, update: true),
      TreeFixture.picker(ids: [-1, -1, 3], update: true),
      TreeFixture.picker(ids: Array(0...256), update: true),
      TreeFixture.children(1, [2, 3]),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
    let valid = TreeFixture.picker(selected: nil, update: true)
    for count in 0..<valid.body.count {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [
              WireOperation(opcode: valid.opcode, body: valid.body.prefix(count))
            ], base: 1, revision: 2))
      }
    }
    #expect(store.revision == 1)
  }

  @Test(arguments: [UInt8(0), 1, 2, 3])
  func nativeStylesSupportNoInitialSelectionAndDisabledControls(style: UInt8) async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame(
          TreeFixture.pickerTree(style: style, selected: nil, enabled: 0))
      ).tree)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    let elements = accessibilityElements(host)
    #expect(!elements.isEmpty)
    #expect(elements.contains { $0.label == "Layout" || $0.value == "Layout" })
    #expect(!elements.contains { $0.role == "AXRadioButton" && $0.enabled })
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualSegmentedNavigationPreservesSignedIDsAndComposedLabels() async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-picker")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root),
          activate: { _ = session.activate($0) }))
      host.sizingOptions = []
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 700, height: 800),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func flush() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
        try await settleAccessibility(host)
      }
      func button(_ title: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first { node in
            guard case .button = node.properties, let child = node.children.first,
              case .text(let text) = child.properties
            else { return false }
            return text.value == title
          })
      }
      func controls(_ view: NSView) -> [NSSegmentedControl] {
        (view as? NSSegmentedControl).map { [$0] } ?? view.subviews.flatMap(controls)
      }
      try await flush()
      let native = try #require(controls(host).first { $0.accessibilityLabel() == "Segmented" })
      let node = try #require(
        session.tree.nodes.values.first {
          if case .picker(let props) = $0.properties { return props.label == "Segmented" }
          return false
        })
      let controller = try #require(node.pickerController)
      #expect(native.segmentCount == 3)
      #expect(native.label(forSegment: 0) == "First" && native.label(forSegment: 1) == "Second")
      #expect(native.image(forSegment: 0) != nil && native.image(forSegment: 1) != nil)
      #expect(!native.isEnabled(forSegment: 2))
      func select(_ index: Int) async throws {
        native.selectedSegment = index
        #expect(native.sendAction(native.action, to: native.target))
        try await flush()
      }
      try await select(1)
      #expect(controller.selection == 2 && native.selectedSegment == 1)
      try await select(2)
      #expect(controller.selection == 2 && native.selectedSegment == 1)
      #expect(session.activate(try button("Ignore picker changes")))
      try await flush()
      try await select(0)
      #expect(controller.selection == 2 && native.selectedSegment == 1)
      #expect(session.activate(try button("Accept picker changes")))
      try await flush()
      #expect(session.activate(try button("Reverse picker options")))
      try await flush()
      #expect(native.label(forSegment: 2) == "First" && native.image(forSegment: 2) != nil)
      try await select(2)
      #expect(controller.selection == -1 && native.selectedSegment == 2)
      #expect(session.activate(try button("Disable pickers")))
      try await flush()
      #expect((0..<3).allSatisfy { !native.isEnabled(forSegment: $0) })
      #expect(!node.emit(.pickerSelection(2)))
      await session.close()
      #expect(!controller.request(2, emit: node.emit))
    } catch {
      await session.close()
      throw error
    }
  }
}
