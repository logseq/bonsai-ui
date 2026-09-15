import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor struct TextFieldWireTests {
  private func fields(_ view: NSView) -> [NSTextField] {
    if let field = view as? NSTextField { return [field] }
    return view.subviews.flatMap(fields)
  }

  @Test(arguments: [47, 49])
  func plainFieldAppearanceRetainsNativeInputAndRestoresRoundedStyle(kind: Int) async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.editor(kind: kind, appearance: 1), TreeFixture.root(1),
      ])
    ).tree
    tree.commit(store)
    tree.onInput = { _, _ in true }
    let controller = try #require(tree.root?.fieldController)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 320, height: 60),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      tree.commit(NodeStore())
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(
      !controller.field.isBezeled && !controller.field.isBordered
        && !controller.field.drawsBackground)
    #expect(controller.field.focusRingType == .none)
    controller.field.selectText(nil)
    let editor = try #require(controller.field.currentEditor() as? NSTextView)
    editor.insertText("Local 🌿", replacementRange: NSRange(location: 0, length: 5))
    try await settleAccessibility(host)
    let revision = controller.session.localRevision
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.editor(
            kind: kind, appearance: 0, document: 2, accepted: revision, mode: 0, update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    try await settleAccessibility(host)
    #expect(tree.root?.fieldController === controller)
    #expect(controller.session.value.text == "Local 🌿")
    #expect(controller.field.isBezeled && controller.field.drawsBackground)
    #expect(controller.field.focusRingType == .default)
  }

  @Test(arguments: [47, 49])
  func nativeFieldsRetainEditingAcrossReorderingAndRejectFutureAcks(kind: Int) async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.create(1),
        TreeFixture.editor(2, kind: kind, label: "First", text: "One"),
        TreeFixture.editor(3, kind: kind, label: "Second", text: "Two", session: 2),
        TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
      ])
    ).tree
    tree.commit(store)
    var edits: [(UInt64, TextEdit)] = []
    tree.onInput = { node, event in
      if case .textEdit(let edit) = event { edits.append((node.id.node, edit)) }
      return true
    }
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 360, height: 140), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      tree.commit(NodeStore())
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    let first = try #require(fields(host).first { $0.accessibilityLabel() == "First" })
    let second = try #require(fields(host).first { $0.accessibilityLabel() == "Second" })
    #expect((first is NSSecureTextField) == (kind == 49))
    first.selectText(nil)
    let editor = try #require(first.currentEditor() as? NSTextView)
    editor.insertText("Local😀", replacementRange: NSRange(location: 0, length: 3))
    try await settleAccessibility(host)
    let edit = try #require(edits.last)
    #expect(edit.0 == 2 && edit.1.value.text == "Local😀")
    let before = try #require(tree.nodes[2])
    let invalid = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.editor(
            2, kind: kind, text: "Invalid", document: 2, accepted: edit.1.localRevision + 1,
            mode: 0, update: true)
        ], base: 1, revision: 2)
    ).tree
    #expect(throws: TextSessionError.self) { try tree.validate(invalid) }
    #expect(tree.revision == 1 && editor.string == "Local😀")
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.editor(
            2, kind: kind, label: "Renamed", prompt: "New prompt", text: "Stale echo", document: 2,
            accepted: edit.1.localRevision, mode: 0, update: true),
          TreeFixture.children(1, [3, 2]),
        ], base: 1, revision: 2)
    ).tree
    try tree.validate(store)
    tree.commit(store)
    try await settleAccessibility(host)
    #expect(tree.nodes[2] === before)
    #expect(fields(host).contains { $0 === first })
    #expect(fields(host).contains { $0 === second })
    #expect(first.stringValue == "Local😀" && second.stringValue == "Two")
    #expect(first.accessibilityLabel() == "Renamed" && first.placeholderString == "New prompt")
    tree.commit(NodeStore())
    #expect(first.delegate == nil && second.delegate == nil)
  }

  @Test(arguments: [47, 49])
  func fieldMalformedSnapshotsBindingsAndChildrenRejectAtomically(kind: Int) throws {
    let store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.editor(kind: kind), TreeFixture.root(1),
      ])
    ).tree
    var invalid = [
      TreeFixture.editor(kind: kind, keyboard: 5, update: true),
      TreeFixture.editor(kind: kind, appearance: 2, update: true),
      TreeFixture.editor(kind: kind, submitLabel: 6, update: true),
      TreeFixture.editor(kind: kind, autofocus: 2, update: true),
      TreeFixture.editor(kind: kind, mode: 3, update: true),
      TreeFixture.editor(kind: kind, enabled: 2, update: true),
      TreeFixture.editor(kind: kind, maximum: 0, update: true),
      TreeFixture.editor(
        kind: kind, text: "😀", selection: NSRange(location: 1, length: 0), update: true),
    ]
    let update = TreeFixture.editor(kind: kind, document: 2, update: true)
    for count in 0..<update.body.count {
      invalid.append(WireOperation(opcode: update.opcode, body: update.body.prefix(count)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
    for operations in [
      [TreeFixture.editor(kind: kind, bindings: []), TreeFixture.root(1)],
      [
        TreeFixture.editor(kind: kind), TreeFixture.text(2, "Child"), TreeFixture.children(1, [2]),
        TreeFixture.root(1),
      ],
    ] {
      #expect(throws: (any Error).self) { try NodeStore().staging(TreeFixture.frame(operations)) }
    }
    #expect(store.revision == 1)
  }
}

extension NativeRuntimeTests {
  @Test(arguments: ["native-field", "native-secure-field"])
  @MainActor func actualOCamlFieldsGatePresentationAndAcknowledgeNativeEdits(entrypoint: String)
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: entrypoint)
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 400, height: 160), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      func fields(_ view: NSView) -> [NSTextField] {
        if let field = view as? NSTextField { return [field] }
        return view.subviews.flatMap(fields)
      }
      let field = try #require(fields(host).first { $0.isEditable })
      #expect((field is NSSecureTextField) == (entrypoint == "native-secure-field"))
      field.selectText(nil)
      let editor = try #require(field.currentEditor() as? NSTextView)
      editor.insertText(
        "Unpresented", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      try await settleAccessibility(host)
      #expect(editor.string == "Draft")
      #expect(try await session.presented(#require(session.ticket)))
      editor.insertText(
        "中文😀", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      try await settleAccessibility(host)
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == "Received: 中文😀" }
          return false
        })
      #expect(fields(host).contains { $0 === field })
      #expect(editor.string == "中文😀")
      editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      try await settleAccessibility(host)
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == "Submitted: 中文😀" }
          return false
        })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualFieldAutofocusRequiresDisplayedActiveApplication() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-autofocus")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 400, height: 160), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      let controller = try #require(session.tree.nodes.values.compactMap(\.fieldController).first)
      window.makeFirstResponder(nil)
      #expect(controller.field.currentEditor() == nil)
      session.isActive = false
      let ticket = try #require(session.ticket)
      #expect(!(try await session.presented(ticket)))
      try await settleAccessibility(host)
      #expect(controller.field.currentEditor() == nil)
      session.isActive = true
      #expect(controller.field.currentEditor() == nil)
      #expect(try await session.presented(ticket))
      try await settleAccessibility(host)
      #expect(controller.field.currentEditor() != nil)
      session.isActive = false
      #expect(controller.field.currentEditor() == nil)
      session.isActive = true
      if try await session.refresh() {
        #expect(try await session.presented(#require(session.ticket)))
      }
      try await settleAccessibility(host)
      #expect(controller.field.currentEditor() == nil)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
