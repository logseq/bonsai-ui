import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor private func composerEditors(_ view: NSView) -> [NativeEditingTextView] {
  if let editor = view as? NativeEditingTextView { return [editor] }
  return view.subviews.flatMap { composerEditors($0) }
}
@MainActor private func composerControl(_ session: BonsaiSession, _ title: String) throws
  -> RenderNodeState
{
  try #require(
    session.tree.nodes.values.first { node in
      node.kind == NodeKindId.button
        && node.children.contains {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        }
    })
}
@MainActor private func composerText(_ session: BonsaiSession, _ text: String) -> Bool {
  session.tree.nodes.values.contains {
    if case .text(let value) = $0.properties { return value.value == text }
    return false
  }
}
@MainActor private func composerAction(_ host: NSView, _ title: String) throws
  -> AccessibilityElement
{
  try #require(accessibilityElements(host).first { $0.role == "AXButton" && $0.label == title })
}

extension NativeRuntimeTests {
  @Test @MainActor func actualComposerOwnsDraftAndRoutesExactRawActions() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-composer")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = host
      defer { window.contentView = nil }
      func flush() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
        try await settleAccessibility(host)
      }
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host)
      #expect(composerEditors(host).count == 1)
      let editor = try #require(composerEditors(host).first)
      #expect(try composerAction(host, "Voice").enabled)
      #expect(!accessibilityElements(host).contains { $0.role == "AXButton" && $0.label == "Send" })
      let raw = "  Hello 👩🏽‍💻\n中文  "
      editor.insertText(raw, replacementRange: NSRange(location: 0, length: 0))
      try await flush()
      #expect(editor.string == raw)
      #expect(composerText(session, "Observed draft: " + raw))
      #expect(
        !accessibilityElements(host).contains { $0.role == "AXButton" && $0.label == "Voice" })
      #expect(try composerAction(host, "Send").press())
      try await flush()
      #expect(composerText(session, "Last action: 3:" + raw))
      #expect(editor.string == raw)
      #expect(try composerAction(host, "Attach").press())
      try await flush()
      #expect(composerText(session, "Last action: 1:" + raw))
      #expect(!session.activate(try composerControl(session, "Custom attachment")))
      editor.setSelectedRange(NSRange(location: 2, length: 5))
      let selection = editor.selectedRange()
      #expect(session.activate(try composerControl(session, "Change composer layout")))
      try await flush()
      #expect(composerEditors(host).first === editor)
      #expect(editor.string == raw)
      #expect(editor.selectedRange() == selection)
      #expect(session.activate(try composerControl(session, "Toggle send")))
      try await flush()
      #expect(!((try composerAction(host, "Send")).enabled))
      #expect((try composerAction(host, "Attach")).enabled)
      #expect(session.activate(try composerControl(session, "Toggle composer")))
      try await flush()
      #expect(!editor.isEditable)
      #expect(!((try composerAction(host, "Attach")).enabled))
      editor.insertText("Rejected", replacementRange: NSRange(location: 0, length: 0))
      #expect(editor.string == raw)
      #expect(session.activate(try composerControl(session, "Toggle composer")))
      try await flush()
      #expect(editor.isEditable)
      #expect(try composerAction(host, "Collapse composer").press())
      try await settleAccessibility(host)
      #expect(composerEditors(host).first === editor)
      #expect(editor.string == raw)
      #expect(session.activate(try composerControl(session, "Reset draft")))
      try await flush()
      let replacement = try #require(composerEditors(host).first)
      #expect(replacement !== editor)
      #expect(replacement.string.isEmpty)
      #expect(session.activate(try composerControl(session, "Remove composer")))
      try await flush()
      #expect(composerEditors(host).isEmpty)
      #expect(session.activate(try composerControl(session, "Remove composer")))
      try await flush()
      #expect(composerEditors(host).first?.string == "")
      await session.close()
      #expect(editor.delegate == nil)
      #expect(replacement.delegate == nil)
    } catch {
      await session.close()
      throw error
    }
  }

  @Test @MainActor func composerRetainsMarkedTextAndRejectsUnadmittedEdits() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-composer")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = host
      defer { window.contentView = nil }
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host)
      let editor = try #require(composerEditors(host).first)
      editor.setMarkedText(
        "拼音", selectedRange: NSRange(location: 2, length: 0),
        replacementRange: NSRange(location: 0, length: 0))
      #expect(editor.hasMarkedText())
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host)
      let marked = editor.markedRange()
      #expect(session.activate(try composerControl(session, "Change composer layout")))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host)
      #expect(editor.hasMarkedText())
      #expect(editor.markedRange() == marked)
      #expect(editor.string == "拼音")
      editor.insertText("中文", replacementRange: marked)
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host)
      let change = try composerControl(session, "Toggle send")
      for _ in 0..<1024 { #expect(session.activate(change)) }
      editor.insertText("Rejected", replacementRange: NSRange(location: 2, length: 0))
      #expect(editor.string == "中文")
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      try await settleAccessibility(host)
      editor.insertText(
        String(repeating: "x", count: ProtocolLimits.maxStringBytes + 1),
        replacementRange: NSRange(location: 0, length: 0))
      #expect(editor.string == "中文")
      try await settleAccessibility(host)
      #expect(
        accessibilityElements(host).contains {
          $0.label == "Draft limit reached" || $0.value == "Draft limit reached"
        })
      session.isVisible = false
      editor.insertText("Hidden", replacementRange: NSRange(location: 0, length: 0))
      #expect(editor.string == "中文")
      session.isVisible = true
      await session.close()
      #expect(editor.delegate == nil)
    } catch {
      await session.close()
      throw error
    }
  }

  @Test @MainActor func composerChildValidationPrecedesResourceCreationAndCoversCachedProps()
    async throws
  {
    let runtime = try await NativeRuntime.open(entrypoint: "native-composer")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let store = try NodeStore().staging(WireFrame.decode(output.bytes)).tree
      let composer = try #require(store.nodes.values.first { $0.kind == NodeKindId.nativeWidget })
      let tree = RenderTree()
      try tree.validate(store)
      tree.commit(store)
      let original = tree.root
      let candidate = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.text(999999, "Unexpected action"),
            TreeFixture.children(composer.id, composer.children + [999999]),
          ], base: store.revision, revision: store.revision + 1, epoch: store.epoch)
      ).tree
      #expect(throws: TreeError.invalidChildren) { try tree.validate(candidate) }
      #expect(tree.root === original)
      #expect(tree.revision == store.revision)
      let fresh = RenderTree()
      #expect(throws: TreeError.invalidChildren) { try fresh.validate(candidate) }
      #expect(fresh.root == nil)
      tree.commit(NodeStore())
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func composerRejectsMalformedPayloadAndReservedRegistration() async throws {
    var registry = BonsaiNativeViews()
    #expect(throws: BonsaiNativeViewError.invalidRegistration) {
      try registry.register(
        kind: 6, version: 1, decode: { _ in () },
        encodeEvent: { (_: Bool) in BonsaiNativeEvent(id: 1) },
        makeResource: { () }, dispose: { _ in }, content: { _ in Text("Override") })
    }
    let runtime = try await NativeRuntime.open(entrypoint: "native-composer")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let store = try NodeStore().staging(WireFrame.decode(output.bytes)).tree
      let node = try #require(store.nodes.values.first { $0.kind == NodeKindId.nativeWidget })
      guard case .nativeView(let envelope) = node.properties else {
        throw TreeError.invalidProperties
      }
      func candidate(_ payload: Data) throws -> NodeStore {
        let operation = TreeFixture.operation(OperationId.updateProps) {
          $0.integer(node.id)
          $0.integer(UInt16(NodeKindId.nativeWidget))
          $0.integer(UInt64(15))
          $0.integer(envelope.kind)
          $0.integer(envelope.version)
          $0.integer(envelope.capabilities.rawValue)
          $0.integer(UInt32(payload.count))
          $0.bytes.append(payload)
        }
        return try store.staging(
          TreeFixture.frame(
            [operation], base: store.revision, revision: store.revision + 1, epoch: store.epoch)
        ).tree
      }
      try RenderTree().validate(store)
      for length in 0..<envelope.payload.count {
        #expect(throws: (any Error).self) {
          try RenderTree().validate(candidate(envelope.payload.prefix(length)))
        }
      }
      for (offset, byte): (Int, UInt8) in [(0, 4), (1, 1), (2, 0), (6, 1), (7, 1), (12, 255)] {
        var invalid = envelope.payload
        invalid[offset] = byte
        #expect(throws: (any Error).self) { try RenderTree().validate(candidate(invalid)) }
      }
      var extra = envelope.payload
      extra.append(0)
      #expect(throws: (any Error).self) { try RenderTree().validate(candidate(extra)) }
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func composerObservesDistinctUtf8SpellingsOfEquivalentText() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-composer")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = host
      defer { window.contentView = nil }
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host)
      let editor = try #require(composerEditors(host).first)
      editor.insertText("\u{00E9}", replacementRange: NSRange(location: 0, length: 0))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host)
      #expect(composerText(session, "Changes: 1"))
      let decomposed = "e\u{0301}"
      editor.insertText(decomposed, replacementRange: NSRange(location: 0, length: 1))
      #expect(editor.string.utf8.elementsEqual(decomposed.utf8))
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      #expect(composerText(session, "Changes: 2"))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
