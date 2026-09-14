import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test(arguments: [360.0, 620.0]) @MainActor
  func actualDropdownCombinesQueryStatesAndIndependentSelections(width: Double) async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    func contains(_ title: String, _ node: RenderNodeState) -> Bool {
      if case .text(let text) = node.properties { return text.value == title }
      return node.children.contains { contains(title, $0) }
    }
    func toggle(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          $0.booleanControlController != nil && contains(title, $0)
        })
    }
    func picker() throws -> RenderNodeState {
      try #require(session.tree.nodes.values.first { $0.pickerController != nil })
    }
    func popup(in view: NSView) -> NSPopUpButton? {
      (view as? NSPopUpButton) ?? view.subviews.lazy.compactMap { popup(in: $0) }.first
    }
    do {
      try await session.start(entrypoint: "native-dropdown")
      let root = try #require(session.tree.root)
      let fieldNode = try #require(session.tree.nodes.values.first { $0.fieldController != nil })
      let field = try #require(fieldNode.fieldController)
      let hosting = NSHostingView(
        rootView:
          NativeNodeView(node: root, activate: { session.activate($0) }).frame(
            width: width, height: 780))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: width, height: 780),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = hosting
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(hosting)
      #expect(try await session.presented(#require(session.ticket)))
      func flush() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
        try await settleAccessibility(hosting)
      }
      func press(_ title: String) async throws {
        let native = try #require(
          accessibilityElements(hosting).first {
            $0.role == "AXButton" && $0.label == title
          })
        _ = native.press()
        try await flush()
      }
      func query(_ text: String) async throws {
        field.field.selectText(nil)
        let editor = try #require(field.field.currentEditor() as? NSTextView)
        editor.insertText(
          text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        try await settleAccessibility(hosting)
        try await flush()
        #expect(field.session.value.text == text)
        #expect(contains("Query: " + text, root))
      }
      func choose(_ title: String) async throws {
        let native = try #require(popup(in: hosting))
        native.selectItem(withTitle: title)
        #expect(native.sendAction(native.action, to: native.target))
        try await flush()
      }
      func set(_ title: String, _ value: Bool) throws {
        let node = try toggle(title)
        #expect(try #require(node.booleanControlController).request(value, emit: node.emit))
      }
      try await choose("Archive")
      #expect(contains("Single: 9", root))
      let originalPicker = try picker()
      let staleChoice = try #require(originalPicker.pickerController).binding(
        emit: originalPicker.emit)
      _ = staleChoice.wrappedValue
      try await query("中文😀")
      #expect(try picker() === originalPicker)
      #expect(originalPicker.pickerController?.selection == nil)
      #expect(contains("Single: 9", root))
      #expect(
        try #require(popup(in: hosting)).itemArray.filter { $0.isEnabled }.map(\.title) == ["中文😀"])
      staleChoice.wrappedValue = -7
      try await flush()
      #expect(contains("Single: 9", root))
      try await choose("中文😀")
      #expect(contains("Single: 13", root))
      try await press("Clear query")
      #expect(field.field.stringValue.isEmpty)
      #expect(try picker() === originalPicker)
      let disabled = try #require(popup(in: hosting)?.itemArray.first { $0.title == "Unavailable" })
      #expect(!disabled.isEnabled)
      #expect(!originalPicker.emit(.pickerSelection(17)))
      try await press("Use multiple selection")
      #expect(!originalPicker.emit(.pickerSelection(-7)))
      try set("Inbox", true)
      try set("Archive", true)
      try await flush()
      #expect(contains("Multiple: -7,9", root))
      let oldInbox = try toggle("Inbox")
      let oldArchive = try toggle("Archive")
      try await query("Archive")
      #expect(try toggle("Archive") === oldArchive)
      #expect(!oldInbox.emit(.valueChanged(false)))
      try set("Archive", false)
      try await flush()
      #expect(contains("Multiple: -7", root))
      try await query("missing")
      #expect(contains("No matching choices", root))
      #expect(session.tree.nodes.values.allSatisfy { $0.booleanControlController == nil })
      try await press("Show loading")
      #expect(contains("Loading choices", root))
      #expect(!oldArchive.emit(.valueChanged(true)))
      try await press("Show error")
      #expect(contains("Choices could not be loaded", root))
      try await press("Retry choices")
      #expect(contains("No matching choices", root))
      #expect(field.field.stringValue == "missing")
      try await press("Show empty")
      #expect(contains("No choices available", root))
      try await press("Show items")
      try await press("Clear query")
      #expect(try toggle("Inbox").booleanControlController?.value == true)
      #expect(try toggle("Archive").booleanControlController?.value == false)
      try await press("Reject selection changes")
      try set("Archive", true)
      try await flush()
      #expect(try toggle("Archive").booleanControlController?.value == false)
      #expect(contains("Multiple: -7", root))
      try await press("Accept selection changes")
      try await press("Disable choices")
      #expect(!field.field.isEnabled)
      #expect(try !toggle("Inbox").emit(.valueChanged(false)))
      try await press("Enable choices")
      #expect(field.field.isEnabled)
      #expect(session.tree.nodes[fieldNode.id.node]?.fieldController === field)
      try await press("Use single selection")
      #expect(try picker().pickerController?.selection == 13)
      #expect(contains("Multiple: -7", root))
      try await press("Reject selection changes")
      try await choose("Inbox")
      #expect(try picker().pickerController?.selection == 13)
      #expect(try #require(popup(in: hosting)).selectedItem?.title == "中文😀")
      await session.close()
      #expect(!oldArchive.emit(.valueChanged(true)))
    } catch {
      await session.close()
      throw error
    }
  }
}
