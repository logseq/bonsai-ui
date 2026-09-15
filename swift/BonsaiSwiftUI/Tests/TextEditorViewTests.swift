import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func editor(
    _ id: UInt64 = 1, kind: Int = 6, label: String = "Title", prompt: String = "Enter title",
    keyboard: UInt8 = 0, submitLabel: UInt8 = 0, autofocus: UInt8 = 0, appearance: UInt8 = 0,
    text: String = "Draft", session: UInt64 = 1,
    document: UInt64 = 1, accepted: UInt64 = 0, mode: UInt8 = 2,
    enabled: UInt8 = 1, readOnly: UInt8 = 0, submit: UInt8 = 0,
    maximum: UInt32? = nil, selection: NSRange? = nil,
    marked: NSRange? = nil, update: Bool = false,
    bindings: [(Int, UInt64)] = [(11, 20), (12, 21), (10, 22), (24, 23)]
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(kind))
      if update { $0.integer(UInt64(kind == 6 ? 511 : 32767)) }
      $0.integer(session)
      $0.integer(document)
      $0.integer(accepted)
      $0.integer(mode)
      $0.integer(UInt32(text.utf8.count))
      $0.bytes.append(contentsOf: text.utf8)
      $0.textRange(selection ?? NSRange(location: text.utf16.count, length: 0))
      $0.integer(UInt8(marked == nil ? 0 : 1))
      if let marked { $0.textRange(marked) }
      $0.integer(enabled)
      $0.integer(readOnly)
      $0.integer(submit)
      $0.integer(UInt8(maximum == nil ? 0 : 1))
      if let maximum { $0.integer(maximum) }
      if kind != 6 {
        for string in [label, prompt] {
          $0.integer(UInt32(string.utf8.count))
          $0.bytes.append(contentsOf: string.utf8)
        }
        $0.bytes.append(contentsOf: [keyboard, submitLabel, autofocus, appearance])
      }
      if !update {
        $0.integer(UInt16(bindings.count))
        for (tag, handler) in bindings {
          $0.integer(UInt16(tag))
          $0.integer(handler)
        }
      }
    }
  }
}

struct TextEditorWireTests {
  @Test @MainActor func retainedControllerValidatesFutureAcksBeforePublishingAnyNode() throws {
    let model = RenderTree()
    model.onInput = { _, _ in true }
    let initial = try NodeStore().staging(
      TreeFixture.frame([TreeFixture.editor(), TreeFixture.root(1)])
    ).tree
    try model.validate(initial)
    model.commit(initial)
    let root = try #require(model.root)
    let controller = try #require(root.textController)
    controller.view.insertText("Local", replacementRange: NSRange(location: 0, length: 5))
    let invalid = try initial.staging(
      TreeFixture.frame(
        [
          TreeFixture.editor(text: "Invalid", document: 2, accepted: 2, mode: 0, update: true)
        ], base: 1, revision: 2)
    ).tree
    #expect(throws: TextSessionError.self) { try model.validate(invalid) }
    #expect(model.revision == 1 && model.root === root && controller.view.string == "Local")
    let next = try initial.staging(
      TreeFixture.frame(
        [
          TreeFixture.editor(
            text: "Local", document: 2, accepted: 1, mode: 0, readOnly: 1, update: true)
        ], base: 1, revision: 2)
    ).tree
    try model.validate(next)
    model.commit(next)
    #expect(model.root === root && model.root?.textController === controller)
    #expect(!controller.view.isEditable && controller.view.isSelectable)
    model.commit(NodeStore())
    #expect(controller.view.delegate == nil)
  }

  @Test func editorPropertiesAndBindingsStageAtomically() throws {
    let before = try NodeStore().staging(
      TreeFixture.frame([TreeFixture.editor(), TreeFixture.root(1)])
    ).tree
    let after = try before.staging(
      TreeFixture.frame(
        [
          TreeFixture.editor(text: "中文😀", document: 2, mode: 1, maximum: 64, update: true)
        ], base: 1, revision: 2)
    ).tree
    #expect(after.nodes[1]?.kind == 6 && after.revision == 2)
    var invalid = [
      TreeFixture.editor(mode: 3, update: true), TreeFixture.editor(enabled: 2, update: true),
      TreeFixture.editor(maximum: 0, update: true),
      TreeFixture.editor(session: UInt64.max, update: true),
      TreeFixture.editor(maximum: UInt32(ProtocolLimits.maxStringBytes + 1), update: true),
      TreeFixture.editor(text: "😀", selection: NSRange(location: 1, length: 0), update: true),
      TreeFixture.editor(
        text: "abc", selection: NSRange(location: 0, length: 0),
        marked: NSRange(location: 1, length: 1), update: true),
    ]
    let update = TreeFixture.editor(text: "Next", document: 2, update: true)
    for length in 0..<update.body.count {
      invalid.append(WireOperation(opcode: update.opcode, body: update.body.prefix(length)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try before.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
      #expect(before.revision == 1)
    }
    for operations in [
      [TreeFixture.editor(bindings: []), TreeFixture.root(1)],
      [TreeFixture.editor(bindings: [(EventTagId.press, 1)]), TreeFixture.root(1)],
      [
        TreeFixture.editor(), TreeFixture.text(2, "Child"), TreeFixture.children(1, [2]),
        TreeFixture.root(1),
      ],
    ] {
      #expect(throws: (any Error).self) { try NodeStore().staging(TreeFixture.frame(operations)) }
    }
  }
}

@MainActor func nativeEditor(in root: NSView) -> NativeEditingTextView? {
  if let view = root as? NativeEditingTextView { return view }
  for child in root.subviews { if let view = nativeEditor(in: child) { return view } }
  return nil
}

extension NativeRuntimeTests {
  @Test @MainActor func actualTextExampleMountsInSwiftUIAndAcknowledgesQueuedNativeEdits()
    async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "text-session")
      let root = try #require(session.tree.root)
      let hosting = NSHostingView(rootView: NativeNodeView(node: root, activate: { _ in }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 180),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = hosting
      hosting.layoutSubtreeIfNeeded()
      let view = try #require(nativeEditor(in: hosting))
      #expect(view.frame.width > 100 && view.frame.height > 50)
      let initial = view.string
      view.insertText(
        "Before presentation",
        replacementRange: NSRange(location: 0, length: view.string.utf16.count))
      #expect(view.string == initial)
      #expect(try await session.presented(#require(session.ticket)))
      for text in ["拼", "拼😀", "拼😀音"] {
        view.setMarkedText(
          text, selectedRange: NSRange(location: text.utf16.count, length: 0),
          replacementRange: NSRange(location: 0, length: view.string.utf16.count))
      }
      #expect(view.hasMarkedText())
      #expect(try await session.refresh())
      #expect(session.tree.root === root && nativeEditor(in: hosting) === view)
      #expect(view.string == "拼😀音" && view.markedRange() == NSRange(location: 0, length: 4))
      guard case .textEditor(let properties) = root.properties else {
        throw TextSessionError.invalidRevision
      }
      #expect(
        properties.snapshot.documentRevision == 2 && properties.snapshot.acceptedLocalRevision == 3)
      #expect(try await session.presented(#require(session.ticket)))
      await session.close()
      #expect(view.delegate == nil)
      window.contentView = nil
    } catch {
      await session.close()
      throw error
    }
  }
}
