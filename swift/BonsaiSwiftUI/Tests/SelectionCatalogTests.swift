import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor private final class SelectionCatalogHarness {
  let session = BonsaiSession()
  var host: NSHostingView<NativeNodeView>?
  var window: NSWindow?
  func start() async throws {
    initializeAccessibilityApplication()
    session.isVisible = true
    try await session.start(entrypoint: "native-selection-catalog")
    #expect(try await session.presented(#require(session.ticket)))
    let host = NSHostingView(
      rootView: NativeNodeView(
        node: try #require(session.tree.root), activate: { [session] in session.activate($0) }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 760), styleMask: [.titled],
      backing: .buffered, defer: false)
    self.host = host
    self.window = window
    window.contentView = host
    window.orderFront(nil)
    try await settleAccessibility(host)
  }
  func close() async {
    await session.close()
    window?.orderOut(nil)
    window?.contentView = nil
  }
  func flush() async throws {
    _ = try await session.refresh()
    if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    if let host { try await settleAccessibility(host) }
  }
  func contains(_ title: String) -> Bool {
    session.tree.nodes.values.contains {
      if case .text(let text) = $0.properties { return text.value == title }
      return false
    }
  }
  func control(_ title: String) throws -> RenderNodeState {
    var node = try #require(
      session.tree.nodes.values.first {
        if case .text(let text) = $0.properties { return text.value == title }
        return false
      })
    while node.booleanControlController == nil {
      if case .button = node.properties { return node }
      let child = node
      node = try #require(session.tree.nodes.values.first { $0.children.contains { $0 === child } })
    }
    return node
  }
  func press(_ title: String) async throws {
    #expect(session.activate(try control(title)))
    try await flush()
  }
  func query() throws -> RenderNodeState {
    try #require(session.tree.nodes.values.first { $0.fieldController != nil })
  }
  func picker() throws -> RenderNodeState {
    try #require(session.tree.nodes.values.first { $0.pickerController != nil })
  }
  func queueEdit(_ value: String) throws {
    let field = try #require(query().fieldController).field
    field.selectText(nil)
    let editor = try #require(field.currentEditor() as? NSTextView)
    editor.insertText(
      value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
  }
  func edit(_ value: String) async throws {
    try queueEdit(value)
    try await settleAccessibility(#require(host))
    try await flush()
  }
  func multiple(_ title: String, _ value: Bool) throws -> Bool {
    let node = try control("Multiple " + title)
    return try #require(node.booleanControlController).request(value, emit: node.emit)
  }
}

@MainActor private func withSelectionCatalog(_ body: (SelectionCatalogHarness) async throws -> Void)
  async throws
{
  let harness = SelectionCatalogHarness()
  do {
    try await harness.start()
    try await body(harness)
    await harness.close()
  } catch {
    await harness.close()
    throw error
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func searchableChoicesPreserveCanonicalSelectionAcrossFilteringAndContentStates()
    async throws
  {
    try await withSelectionCatalog { h in
      let query = try h.query()
      let single = try h.picker()
      let archive = try h.control("Multiple Archive")
      #expect(try #require(single.pickerController).request(9, emit: single.emit))
      #expect(try h.multiple("Archive", true))
      try await h.flush()
      #expect(h.contains("Selected single: Archive"))
      #expect(h.contains("Selected multiple: Inbox, Archive"))
      try await h.edit("Inbox")
      #expect(try h.query() === query)
      #expect(try h.picker().pickerController?.selection == nil)
      #expect(!archive.booleanControlController!.request(false, emit: archive.emit))
      #expect(h.contains("Selected single: Archive"))
      try await h.edit("missing")
      #expect(h.contains("No matching choices"))
      #expect(
        h.session.tree.nodes.values.allSatisfy {
          $0.pickerController == nil && $0.booleanControlController == nil
        })
      for (action, message) in [
        ("Show loading", "Loading choices"), ("Show empty", "No choices available"),
        ("Show error", "Choices could not be loaded"),
      ] {
        try await h.press(action)
        #expect(h.contains(message))
        #expect(try h.query() === query)
        #expect(h.contains("Selected multiple: Inbox, Archive"))
      }
      try await h.press("Retry choices")
      #expect(h.contains("No matching choices"))
      try await h.edit("")
      #expect(try h.picker().pickerController?.selection == 9)
      #expect(try h.control("Multiple Archive").booleanControlController?.value == true)
      #expect(try h.query() === query)
      try await h.press("Clear selections")
      #expect(try h.picker().pickerController?.selection == nil)
      #expect(h.contains("Selected multiple: None"))
    }
  }

  @Test @MainActor func choiceLayoutsKeepModelStateAndRejectHiddenDisabledOrIgnoredRequests()
    async throws
  {
    try await withSelectionCatalog { h in
      #expect(try h.multiple("Archive", true))
      try await h.flush()
      let old = try h.control("Multiple Archive")
      try await h.press("Use scrolling")
      #expect(
        h.session.tree.nodes.values.contains {
          if case .scroll = $0.properties { return true }
          return false
        })
      #expect(h.contains("Selected multiple: Inbox, Archive"))
      try await h.press("Use vertical layout")
      #expect(h.contains("Layout: Vertical"))
      try await h.press("Use menus")
      #expect(!old.booleanControlController!.request(false, emit: old.emit))
      let menu = try #require(
        h.session.tree.nodes.values.first { $0.menuController?.checked(9) == true })
      #expect(menu.menuController!.select(9, emit: menu.emit))
      #expect(menu.menuController!.select(9, emit: menu.emit))
      try await h.flush()
      #expect(menu.menuController!.checked(9))
      try await h.press("Ignore selection changes")
      #expect(menu.menuController!.select(9, emit: menu.emit))
      #expect(!(try await h.session.refresh()))
      #expect(menu.menuController!.checked(9))
      let single = try h.picker()
      #expect(single.pickerController!.request(9, emit: single.emit))
      #expect(!(try await h.session.refresh()))
      #expect(single.pickerController!.selection == -7)
      try await h.press("Disable catalog")
      #expect(!menu.menuController!.select(-7, emit: menu.emit))
      #expect(!single.pickerController!.request(9, emit: single.emit))
      #expect(try h.query().fieldController?.field.isEnabled == false)
      try await h.press("Enable catalog")
      try await h.press("Accept selection changes")
      try await h.press("Use wrapping")
      try await h.press("Use horizontal layout")
      #expect(try h.control("Multiple Archive").booleanControlController?.value == true)
      let retained = try h.control("Multiple Inbox")
      try await h.press("Reverse choices")
      #expect(try h.control("Multiple Inbox") === retained)
      let action = try h.control("Open Inbox")
      #expect(h.session.activate(action))
      #expect(h.session.activate(action))
      try await h.flush()
      #expect(h.contains("Actions: 2 (Inbox)"))
      #expect(!h.session.activate(try h.control("Open Unavailable")))
      for _ in 0..<5 { try await h.press("Change control size") }
      #expect(h.contains("Control size: Regular"))
    }
  }

  @Test @MainActor
  func choiceSearchPreservesUnicodeSelectionAndMarkedTextThroughOcamlAcknowledgments() async throws
  {
    try await withSelectionCatalog { h in
      let query = try h.query()
      let field = try #require(query.fieldController).field
      field.selectText(nil)
      let editor = try #require(field.currentEditor() as? NSTextView)
      editor.setMarkedText(
        "中文😀", selectedRange: NSRange(location: 4, length: 0),
        replacementRange: NSRange(location: 0, length: 0))
      try await settleAccessibility(#require(h.host))
      try await h.flush()
      #expect(editor.string == "中文😀")
      #expect(editor.markedRange() == NSRange(location: 0, length: 4))
      #expect(try h.picker().children.count == 1)
      editor.unmarkText()
      try await settleAccessibility(#require(h.host))
      try await h.flush()
      #expect(try h.query() === query)
      #expect(try h.query().fieldController?.session.value.text == "中文😀")
      #expect(h.contains("Selected single: Inbox"))
      try await h.edit("")
      #expect(try h.picker().pickerController?.selection == -7)
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func choicePickerAdaptersFollowAllFiveNativeControlSizes() async throws {
    try await withSelectionCatalog { h in
      @MainActor func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
      }
      for layout in ["Use wrapping", "Use vertical layout", "Use menus"] {
        try await h.press(layout)
        for expected: NSControl.ControlSize in [.regular, .large, .extraLarge, .mini, .small] {
          let controls = descendants(try #require(h.host)).compactMap { view -> NSControl? in
            guard let control = view as? NSControl else { return nil }
            let label = control.accessibilityLabel() ?? ""
            return label == "Single choice" || label.hasPrefix("Single ") ? control : nil
          }
          #expect(!controls.isEmpty)
          for control in controls {
            #expect(control.controlSize == expected)
            #expect(control.bounds.height >= control.intrinsicContentSize.height)
          }
          try await h.press("Change control size")
        }
      }
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func choiceEventsQueuedAfterFilteringCannotChangeHiddenCanonicalChoices()
    async throws
  {
    try await withSelectionCatalog { h in
      #expect(try h.multiple("Archive", true))
      try await h.flush()
      let archive = try h.control("Multiple Archive")
      let picker = try h.picker()
      try h.queueEdit("Inbox")
      // Native selection notifications capture the completed edit on the next MainActor task.
      // Let that event enter the queue before later choices, without pumping OCaml yet.
      try await settleAccessibility(#require(h.host))
      #expect(try h.query().fieldController?.session.value.text == "Inbox")
      #expect(archive.booleanControlController!.request(false, emit: archive.emit))
      #expect(picker.pickerController!.request(9, emit: picker.emit))
      try await h.flush()
      #expect(h.contains("Selected multiple: Inbox, Archive"))
      #expect(h.contains("Selected single: Inbox"))
      #expect(!h.contains("Single Archive"))
      try await h.edit("")
      #expect(try h.control("Multiple Archive").booleanControlController?.value == true)
      #expect(try h.picker().pickerController?.selection == -7)
    }
  }
}
