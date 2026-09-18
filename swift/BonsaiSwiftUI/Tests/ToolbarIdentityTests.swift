import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor struct ToolbarIdentityTests {
  @Test(arguments: [
    (UInt64(2), 47, false), (2, 47, true), (3, 47, false), (3, 47, true),
    (4, 47, false), (4, 47, true), (3, 49, false), (4, 49, false),
    (3, 6, false), (3, 6, true), (4, 6, false), (4, 6, true),
  ])
  func nativeFrameworkFieldsRetainFocusAcrossKeyedGroupMoves(scenario: (UInt64, Int, Bool))
    async throws
  {
    let (focused, kind, composing) = scenario
    initializeAccessibilityApplication()
    let tree = RenderTree()
    let base = TreeFixture.toolbarTree().filter { operation in
      var reader = WireReader(operation.body)
      let id = try? reader.integer(UInt64.self)
      if operation.opcode == OperationId.setChildren && id == 22 { return false }
      guard operation.opcode == OperationId.createNode else { return true }
      return id != 2 && id != 3 && id != 4 && id != 22
    }
    var widths: [WireOperation] = []
    for id: UInt64 in [3, 4] {
      widths.append(
        TreeFixture.operation(OperationId.createNode) {
          $0.integer(id + 30)
          $0.integer(UInt16(22))
          $0.integer(UInt8(1))
          $0.integer(Double(120).bitPattern)
          for _ in 0..<7 { $0.integer(UInt8(0)) }
          $0.integer(UInt8(4))
          $0.integer(UInt16(0))
        })
      widths.append(TreeFixture.children(id + 30, [id]))
      widths.append(TreeFixture.children(id == 3 ? 21 : 22, [id + 30]))
    }
    var store = try NodeStore().staging(
      TreeFixture.frame(
        base + [
          TreeFixture.editor(2, kind: focused == 2 ? kind : 47, label: "Body", text: "One"),
          TreeFixture.editor(
            3, kind: focused == 3 ? kind : 47, label: "First", text: "One", session: 2),
          TreeFixture.editor(
            4, kind: focused == 4 ? kind : 47, label: "Second", text: "Two", session: 3),
          TreeFixture.toolbarChild(22, key: "second"), TreeFixture.toolbarChild(23, key: "label"),
          TreeFixture.text(5, "Other group"), TreeFixture.children(23, [5]),
          TreeFixture.children(11, [21, 22]), TreeFixture.children(12, [23]),
        ] + widths)
    ).tree
    tree.commit(store)
    var inputs: [(UInt64, NativeEventPayload)] = []
    tree.onInput = { node, payload in
      inputs.append((node.id.node, payload))
      return true
    }
    let host = NSHostingController(
      rootView:
        NativeNodeView(node: try #require(tree.root), activate: { _ in }).frame(
          width: 650, height: 300))
    host.sceneBridgingOptions = .all
    let window = NSWindow(contentViewController: host)
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentViewController = nil
    }
    func commit(_ operations: [WireOperation]) throws {
      store = try store.staging(
        TreeFixture.frame(
          operations, base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
    }
    try await settleAccessibility(host.view)
    let focus = try #require(tree.nodes[focused])
    func currentSession() -> TextSession {
      focus.fieldController?.session ?? focus.textController!.session
    }
    let field = focus.fieldController?.field
    let nativeView: NSView = field ?? focus.textController!.view
    func nativeEditor() -> NSTextView? {
      if let field { return field.currentEditor() as? NSTextView }
      return window.firstResponder === focus.textController?.view ? focus.textController?.view : nil
    }
    func verifyNativeOwnership(_ order: [UInt64]) throws {
      let entries = try #require(window.toolbar).items.filter {
        $0.itemIdentifier.rawValue.hasPrefix("bonsai-")
      }
      #expect(entries.map(\.itemIdentifier.rawValue) == order.map { "bonsai-\(store.epoch)-\($0)" })
      #expect(entries.allSatisfy { $0 is NSToolbarItemGroup })
      func views(_ items: [NSToolbarItem]) -> [NSView] {
        items.compactMap(\.view)
          + items.flatMap { ($0 as? NSToolbarItemGroup).map { views($0.subitems) } ?? [] }
      }
      let native = views(entries)
      for id: UInt64 in [3, 4] {
        let node = try #require(tree.nodes[id])
        let view: NSView = node.fieldController?.field ?? node.textController!.view
        #expect(view.window === window)
        #expect(native.contains { view.isDescendant(of: $0) })
      }
    }
    try verifyNativeOwnership([11, 12])
    #expect(nativeView.window === window)
    if let field { field.selectText(nil) } else { #expect(window.makeFirstResponder(nativeView)) }
    let editor = try #require(nativeEditor())
    editor.insertText("Local draft", replacementRange: NSRange(location: 0, length: 3))
    try await settleAccessibility(host.view)
    if composing {
      editor.setMarkedText(
        "中", selectedRange: NSRange(location: 1, length: 0),
        replacementRange: NSRange(location: 0, length: 1))
      try await settleAccessibility(host.view)
    }
    let draft = currentSession().value
    func verifyDraft() {
      #expect(currentSession().value == draft)
      #expect(editor.string == draft.text)
      #expect(editor.selectedRange() == draft.selection)
      #expect(editor.hasMarkedText() == composing)
      if composing { #expect(editor.markedRange() == draft.marked) }
    }
    inputs.removeAll()
    try commit([TreeFixture.children(1, [10, 12, 13, 11])])
    try await settleAccessibility(host.view)
    #expect(focus.fieldController?.field === field)
    try verifyNativeOwnership([12, 11])
    #expect(nativeEditor() === editor)
    #expect(window.firstResponder === editor)
    verifyDraft()
    try commit([TreeFixture.children(11, [22, 21])])
    try await settleAccessibility(host.view)
    try verifyNativeOwnership([12, 11])
    #expect(nativeEditor() === editor)
    #expect(window.firstResponder === editor)
    verifyDraft()
    try commit([
      TreeFixture.toolbarEntry(11, key: "first", placement: 2, kind: 1, update: true),
      TreeFixture.toolbarEntry(12, key: "second", placement: 2, kind: 1, update: true),
    ])
    try await settleAccessibility(host.view)
    try verifyNativeOwnership([12, 11])
    #expect(nativeEditor() === editor)
    #expect(window.firstResponder === editor)
    verifyDraft()
    try commit([
      TreeFixture.children(1, [10, 12, 11]),
      TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(13)) },
    ])
    try await settleAccessibility(host.view)
    try verifyNativeOwnership([12, 11])
    #expect(nativeEditor() === editor)
    #expect(window.firstResponder === editor)
    verifyDraft()
    try commit([
      TreeFixture.toolbarEntry(100, key: "fixed", placement: 2, kind: 2),
      TreeFixture.children(1, [10, 12, 100, 11]),
    ])
    try await settleAccessibility(host.view)
    try verifyNativeOwnership([12, 11])
    #expect(nativeEditor() === editor)
    #expect(window.firstResponder === editor)
    verifyDraft()
    if composing {
      #expect(
        !inputs.contains {
          if case .textEdit(let edit) = $0.1 { return edit.value.marked != draft.marked }
          return false
        })
    }
    #expect(
      !inputs.contains {
        if case .focusChanged = $0.1 { return true }
        return false
      })
    try commit([
      TreeFixture.editor(
        focused, kind: kind, label: "Updated", text: "Authoritative",
        session: currentSession().sessionID, document: 2,
        accepted: currentSession().localRevision, selection: NSRange(location: 2, length: 0),
        update: true),
      TreeFixture.children(1, [10, 11, 100, 12]),
    ])
    try await settleAccessibility(host.view)
    #expect(nativeEditor() === editor)
    #expect(editor.string == "Authoritative")
    #expect(editor.selectedRange() == NSRange(location: 2, length: 0))
    #expect(!editor.hasMarkedText())
    try commit([TreeFixture.children(1, [10, 12, 100, 11])])
    let other = try #require(tree.nodes[focused == 3 ? 4 : 3]?.fieldController?.field)
    other.selectText(nil)
    try await settleAccessibility(host.view)
    #expect(other.currentEditor() === window.firstResponder)
    #expect(nativeEditor() == nil)
  }
}

extension ToolbarIdentityTests {
  @Test(arguments: ["disabled", "hidden", "binding", "session", "expired", "disposed"])
  func toolbarFocusTransferCannotReviveInvalidatedInput(reason: String) async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    let base = TreeFixture.toolbarTree().filter {
      guard $0.opcode == OperationId.createNode else { return true }
      var reader = WireReader($0.body)
      return (try? reader.integer(UInt64.self)) != 3
    }
    var store = try NodeStore().staging(
      TreeFixture.frame(
        base + [
          TreeFixture.editor(3, kind: 47, text: "Draft"),
          TreeFixture.operation(OperationId.createNode) {
            $0.integer(UInt64(33))
            $0.integer(UInt16(22))
            $0.integer(UInt8(1))
            $0.integer(Double(120).bitPattern)
            for _ in 0..<7 { $0.integer(UInt8(0)) }
            $0.integer(UInt8(4))
            $0.integer(UInt16(0))
          }, TreeFixture.children(33, [3]), TreeFixture.children(21, [33]),
        ])
    ).tree
    tree.onInput = { _, _ in true }
    tree.commit(store)
    let host = NSHostingController(
      rootView:
        NativeNodeView(node: try #require(tree.root), activate: { _ in }).frame(
          width: 650, height: 300))
    host.sceneBridgingOptions = .all
    let window = NSWindow(contentViewController: host)
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentViewController = nil
    }
    try await settleAccessibility(host.view)
    let node = try #require(tree.nodes[3])
    let controller = try #require(node.fieldController)
    let field = controller.field
    field.selectText(nil)
    #expect(field.currentEditor() != nil)
    func commit(_ operations: [WireOperation]) throws {
      store = try store.staging(
        TreeFixture.frame(
          operations,
          base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
    }
    try commit([TreeFixture.children(1, [10, 12, 13, 11])])
    switch reason {
    case "disabled":
      try commit([TreeFixture.editor(3, kind: 47, text: "Draft", enabled: 0, update: true)])
    case "hidden":
      controller.setContentActive(false)
      window.orderOut(nil)
    case "binding":
      try commit([
        TreeFixture.operation(OperationId.updateEventBindings) {
          $0.integer(UInt64(3))
          $0.integer(UInt16(4))
          for (tag, handler): (UInt16, UInt64) in [(11, 120), (12, 121), (10, 122), (24, 123)] {
            $0.integer(tag)
            $0.integer(handler)
          }
        }
      ])
      window.makeFirstResponder(nil)
    case "session":
      try commit([TreeFixture.editor(3, kind: 47, text: "New session", session: 2, update: true)])
      window.makeFirstResponder(nil)
    case "expired":
      let toolbar = window.toolbar
      window.toolbar = nil
      window.makeFirstResponder(nil)
      try await Task.sleep(for: .milliseconds(650))
      window.toolbar = toolbar
    case "disposed":
      let drops = store.nodes.keys.map { id in
        TreeFixture.operation(OperationId.dropNode) { $0.integer(id) }
      }
      try commit(drops + [TreeFixture.text(100, "Replacement"), TreeFixture.root(100)])
      host.rootView = NativeNodeView(node: try #require(tree.root), activate: { _ in })
        .frame(width: 650, height: 300)
    default: Issue.record("Unexpected invalidation")
    }
    try await settleAccessibility(host.view)
    if reason == "disabled" {
      try commit([TreeFixture.editor(3, kind: 47, text: "Draft", update: true)])
    }
    if reason == "hidden" {
      controller.setContentActive(true)
      window.orderFront(nil)
    }
    try await settleAccessibility(host.view)
    #expect(field.currentEditor() == nil)
    #expect(!controller.hasToolbarFocusTransfer)
    if reason == "disposed" { #expect(!field.isEnabled) }
  }
}
