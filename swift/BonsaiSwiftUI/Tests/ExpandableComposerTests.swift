import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor private final class ExpandedComposerHarness {
  let session = BonsaiSession()
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 700, height: 700), styleMask: [.titled],
    backing: .buffered, defer: false)
  var host: NSView { window.contentView! }
  func start() async throws {
    initializeAccessibilityApplication()
    session.isVisible = true
    try await session.start(entrypoint: "native-expandable-composer")
    window.contentView = NSHostingView(
      rootView: NativeNodeView(
        node: try #require(session.tree.root), activate: { [session] in _ = session.activate($0) }))
    window.orderFront(nil)
    try await settle { true }
  }
  func close() async {
    await session.close()
    window.orderOut(nil)
    window.contentView = nil
  }
  func control(_ title: String) throws -> RenderNodeState {
    try #require(
      session.tree.nodes.values.first { node in
        node.kind == NodeKindId.button
          && node.children.contains {
            if case .text(let value) = $0.properties { return value.value == title }
            return false
          }
      })
  }
  func contains(_ title: String) -> Bool {
    session.tree.nodes.values.contains {
      if case .text(let value) = $0.properties { return value.value == title }
      return false
    }
  }
  var sheet: NSWindow? {
    window.sheets.first
  }
  func editors(_ view: NSView) -> [NativeEditingTextView] {
    if let editor = view as? NativeEditingTextView { return [editor] }
    return view.subviews.flatMap { editors($0) }
  }
  func button(_ title: String, in view: NSView) throws -> AccessibilityElement {
    try #require(accessibilityElements(view).first { $0.role == "AXButton" && $0.label == title })
  }
  func press(_ title: String) throws {
    #expect(try button(title, in: #require(sheet?.contentView)).press())
  }
  func settle(_ predicate: () -> Bool) async throws {
    for _ in 0..<40 {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      try await settleAccessibility(host)
      if let view = sheet?.contentView { try await settleAccessibility(view) }
      if predicate() { return }
    }
    Issue.record("Expandable composer did not settle")
    throw NSError(domain: "ExpandableComposerTests", code: 1)
  }
  func open() async throws -> NativeEditingTextView {
    #expect(try button("Open composer", in: host).press())
    #expect(!session.activate(try control("Background action")))
    try await settle { sheet?.contentView.map { editors($0).count == 1 } == true }
    let content = try #require(sheet?.contentView)
    return try #require(editors(content).first)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func expandableComposerRetainsDraftAndFencesBackgroundAcrossReopening()
    async throws
  {
    let app = ExpandedComposerHarness()
    do {
      try await app.start()
      let owner = try #require(app.session.tree.nativeViewNodes.first)
      #expect(!app.session.activate(try #require(owner.children.first)))
      let editor = try await app.open()
      let controller = try #require(owner.nativeView?.resource as? ExpandableComposerController)
      let previousBinding = controller.binding(controller.generation)
      editor.setMarkedText(
        "拼音", selectedRange: NSRange(location: 2, length: 0),
        replacementRange: NSRange(location: 0, length: 0))
      try await app.settle { app.contains("Observed draft: 拼音") }
      #expect(editor.hasMarkedText())
      let marked = editor.markedRange()
      let raw = "  中文 👩🏽‍💻\nDraft  "
      editor.insertText(raw, replacementRange: marked)
      try await app.settle { app.contains("Observed draft: " + raw) }
      editor.setSelectedRange(NSRange(location: 2, length: 2))
      let selection = editor.selectedRange()
      try app.press("Send")
      try await app.settle { app.contains("Last action: 3:" + raw) }
      try app.press("Change launcher")
      try await app.settle { editor.accessibilityLabel() == "Compact launcher draft" }
      #expect(app.editors(try #require(app.sheet?.contentView)).first === editor)
      #expect(editor.selectedRange() == selection)
      #expect(!app.session.activate(try app.control("Background action")))
      let oldSend = try app.button("Send", in: #require(app.sheet?.contentView))
      try app.press("Close composer")
      #expect(!app.session.activate(try app.control("Background action")))
      _ = oldSend.press()
      try await app.settle { app.sheet == nil }
      #expect(app.contains("Actions: 2"))
      #expect(app.session.activate(try app.control("Background action")))
      try await app.settle { app.contains("Background: 1") }
      let reopened = try await app.open()
      previousBinding.wrappedValue = false
      try await app.settle { true }
      #expect(app.sheet != nil)
      #expect(controller.requested)
      #expect(reopened === editor)
      #expect(reopened.string == raw)
      #expect(reopened.selectedRange() == selection)
      app.session.isVisible = false
      reopened.insertText("Rejected", replacementRange: NSRange(location: 0, length: 0))
      #expect(reopened.string == raw)
      app.session.isVisible = true
      await app.close()
      #expect(editor.delegate == nil)
      try await app.start()
      previousBinding.wrappedValue = true
      try await app.settle { true }
      #expect(app.sheet == nil)
      let fresh = try await app.open()
      #expect(fresh !== editor)
      #expect(fresh.string.isEmpty)
      await app.close()
    } catch {
      await app.close()
      throw error
    }
  }

  @Test @MainActor func expandableComposerDisableRemoveAndReplaceOwnResources() async throws {
    let app = ExpandedComposerHarness()
    do {
      try await app.start()
      let editor = try await app.open()
      editor.insertText("Retain", replacementRange: NSRange(location: 0, length: 0))
      try await app.settle { app.contains("Observed draft: Retain") }
      try app.press("Disable composer")
      try await app.settle { !editor.isEditable }
      #expect(app.sheet != nil)
      #expect(!(try app.button("Send", in: #require(app.sheet?.contentView))).enabled)
      try app.press("Close composer")
      try await app.settle { app.sheet == nil }
      #expect(!(try app.button("Open composer", in: app.host)).enabled)
      #expect(app.session.activate(try app.control("Toggle availability")))
      try await app.settle { (try? app.button("Open composer", in: app.host).enabled) == true }
      #expect(try await app.open() === editor)
      try app.press("Reset from sheet")
      try await app.settle { app.sheet == nil }
      #expect(editor.delegate == nil)
      let replacement = try await app.open()
      #expect(replacement !== editor)
      #expect(replacement.string.isEmpty)
      try app.press("Remove from sheet")
      try await app.settle { app.sheet == nil }
      #expect(replacement.delegate == nil)
      #expect(app.session.activate(try app.control("Toggle composer visibility")))
      try await app.settle { (try? app.button("Open composer", in: app.host)) != nil }
      let final = try await app.open()
      #expect(final.string.isEmpty)
      await app.close()
      #expect(final.delegate == nil)
    } catch {
      await app.close()
      throw error
    }
  }

  @Test @MainActor func expandableComposerValidatesPayloadChildrenAndReservedKind() async throws {
    var registry = BonsaiNativeViews()
    #expect(throws: BonsaiNativeViewError.invalidRegistration) {
      try registry.register(
        kind: 7, version: 2, decode: { _ in () },
        encodeEvent: { (_: Bool) in BonsaiNativeEvent(id: 1) },
        makeResource: { () }, dispose: { _ in }, content: { _ in Text("Override") })
    }
    let runtime = try await NativeRuntime.open(entrypoint: "native-expandable-composer")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let store = try NodeStore().staging(WireFrame.decode(output.bytes)).tree
      let node = try #require(store.nodes.values.first { $0.kind == NodeKindId.nativeWidget })
      guard case .nativeView(let envelope) = node.properties else {
        throw TreeError.invalidProperties
      }
      let tree = RenderTree()
      try tree.validate(store)
      tree.commit(store)
      func candidate(_ payload: Data, version: UInt16 = 2) throws -> NodeStore {
        let operation = TreeFixture.operation(OperationId.updateProps) {
          $0.integer(node.id)
          $0.integer(UInt16(NodeKindId.nativeWidget))
          $0.integer(UInt64(15))
          $0.integer(envelope.kind)
          $0.integer(version)
          $0.integer(envelope.capabilities.rawValue)
          $0.integer(UInt32(payload.count))
          $0.bytes.append(payload)
        }
        return try store.staging(
          TreeFixture.frame(
            [operation], base: store.revision,
            revision: store.revision + 1, epoch: store.epoch)
        ).tree
      }
      for length in 0..<envelope.payload.count {
        #expect(throws: (any Error).self) {
          try tree.validate(candidate(envelope.payload.prefix(length)))
        }
      }
      for (offset, byte): (Int, UInt8) in [
        (0, 2), (1, 4), (4, 0), (20, 2), (21, 1), (22, 1), (23, 1),
      ] {
        var invalid = envelope.payload
        invalid[offset] = byte
        #expect(throws: (any Error).self) { try tree.validate(candidate(invalid)) }
      }
      for curve: UInt8 in 0...3 {
        for compact: UInt8 in 0...1 {
          for duration: UInt16 in [0, 200, 65535] {
            var valid = envelope.payload
            valid[1] = curve
            valid[2] = UInt8(truncatingIfNeeded: duration)
            valid[3] = UInt8(duration >> 8)
            valid[20] = compact
            try tree.validate(candidate(valid))
            let props = try RenderExpandableComposer.decode(valid)
            #expect(props.animation(reduceMotion: true) == nil)
            #expect((props.animation(reduceMotion: false) == nil) == (duration == 0))
          }
        }
      }
      var extra = envelope.payload
      extra.append(0)
      #expect(throws: (any Error).self) { try tree.validate(candidate(extra)) }
      #expect(throws: BonsaiNativeViewError.incompatibleVersion(7, 1)) {
        try tree.validate(candidate(envelope.payload, version: 1))
      }
      let missing = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.text(999999, "Extra action"),
            TreeFixture.children(node.id, node.children + [999999]),
          ], base: store.revision, revision: store.revision + 1, epoch: store.epoch)
      ).tree
      #expect(throws: TreeError.invalidChildren) { try tree.validate(missing) }
      #expect(tree.revision == store.revision)
      tree.commit(NodeStore())
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
