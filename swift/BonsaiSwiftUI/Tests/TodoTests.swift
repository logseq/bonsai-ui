import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test(arguments: [360, 800]) @MainActor
  func actualTodoEditsReordersCompletesAddsAndDeletesWithoutLosingIdentity(width: Int) async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "todo")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: width, height: 500), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      func field(_ label: String) throws -> NativeTextFieldController {
        try #require(
          session.tree.nodes.values.compactMap(\.fieldController).first {
            $0.field.accessibilityLabel() == label
          })
      }
      func update() async throws {
        try await settleAccessibility(host)
        #expect(try await session.refresh())
        #expect(try await session.presented(#require(session.ticket)))
        try await settleAccessibility(host)
      }
      func press(_ label: String) async throws {
        let button = try #require(
          accessibilityElements(host).first { $0.label == label && $0.role == "AXButton" })
        #expect(button.press())
        try await update()
      }
      let first = try field("Todo 1 title")
      let second = try field("Todo 2 title")
      #expect(first.field.stringValue == "Keep identity")
      #expect(first.field.bounds.width >= 160)
      first.field.selectText(nil)
      let editor = try #require(first.field.currentEditor() as? NSTextView)
      editor.insertText(
        "保留😀", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      try await update()
      #expect(first.field.stringValue == "保留😀")
      #expect(first.session.localRevision > 0)
      try await press("Reverse")
      #expect(try field("Todo 1 title") === first)
      #expect(try field("Todo 2 title") === second)
      #expect(first.field.currentEditor() === editor)
      #expect(editor.string == "保留😀")
      #expect(first.session.value.selection == NSRange(location: 4, length: 0))
      let toggle = try #require(
        accessibilityElements(host).first {
          $0.label == "Complete todo 1" && $0.numericValue != nil
        })
      #expect(toggle.numericValue == 0 && toggle.press())
      try await update()
      #expect(
        accessibilityElements(host).contains {
          $0.label == "Complete todo 1" && $0.numericValue == 1
        })
      try await press("Add")
      #expect(try field("Todo 4 title").field.stringValue == "Todo 4")
      try await press("Select todo 2")
      try await press("Delete todo 1")
      #expect(first.field.delegate == nil)
      #expect(!session.tree.nodes.values.contains { $0.fieldController === first })
      #expect(try field("Todo 2 title") === second)
      #expect(second.field.stringValue == "Preserve focus")
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
