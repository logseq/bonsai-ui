import AppKit
import SwiftUI

private let mode =
  ProcessInfo.processInfo.arguments.contains("--anchored")
  ? 1
  : ProcessInfo.processInfo.arguments.contains("--fullscreen") ? 2 : 0

@main struct SearchWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Search acceptance", id: "search-acceptance") {
      BonsaiApplicationView(entrypoint: "native-search-\(mode)", session: session)
        .frame(minWidth: 640, minHeight: 620)
        .task { await verify(session) }
    }.defaultSize(width: 800, height: 680)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing search window") }
    func contains(_ title: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == title }
        return false
      }
    }
    func wait(_ title: String, _ condition: () -> Bool = { true }) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil && contains(title) && condition() { return }
      }
      let values = session.tree.nodes.values.compactMap { node -> String? in
        if case .text(let text) = node.properties { return text.value }
        return nil
      }
      throw failure("Search did not settle: \(title); state: \(values)")
    }
    func elements() -> [AccessibilityElement] {
      NSApp.windows.flatMap { window in
        (window.toolbar?.items.compactMap(\.view).flatMap { accessibilityElements($0) } ?? [])
          + accessibilityElements(window)
      }
    }
    func control(_ title: String) throws -> AccessibilityElement {
      guard let control = elements().first(where: { $0.role == "AXButton" && $0.label == title })
      else { throw failure("Missing control: \(title)") }
      return control
    }
    func press(_ title: String, until expected: String) async throws {
      let button = try control(title)
      guard button.enabled else { throw failure("Disabled control: \(title)") }
      _ = button.press()
      try await wait(expected)
    }
    func field() throws -> NSTextField {
      guard let field = session.tree.nodes.values.compactMap(\.fieldController).first?.field
      else { throw failure("Missing search field") }
      return field
    }
    func editor() throws -> NSTextView {
      let field = try field()
      field.selectText(nil)
      guard let editor = field.currentEditor() as? NSTextView else {
        throw failure("Missing native editor")
      }
      return editor
    }
    func edit(_ value: String) async throws {
      let editor = try editor()
      editor.insertText(
        value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      try await wait("Query: " + value)
    }
    try await wait("Search: Closed")
    try await press("Open search", until: "Opened: 1")
    try await wait("Search: Open") { (try? field().window) != nil }
    let originalField = try field()
    guard try !control("Choose Unavailable").enabled else {
      throw failure("Disabled suggestion enabled")
    }
    let oldInbox = try control("Choose Inbox")
    try await edit("Archive")
    _ = oldInbox.press()
    try await wait("Selected: None")
    guard !contains("Choose Inbox") else { throw failure("Filtered suggestion remained") }
    try await edit("missing")
    try await wait("No search results")
    try await edit("")
    let editor = try editor()
    editor.setMarkedText(
      "中文😀", selectedRange: NSRange(location: 4, length: 0),
      replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    try await wait("Query: 中文😀")
    guard editor.markedRange() == NSRange(location: 0, length: 4),
      editor.selectedRange() == NSRange(location: 4, length: 0), try field() === originalField
    else { throw failure("Marked text or field identity lost") }
    editor.unmarkText()
    try await settleAccessibility(host)
    editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    try await wait("Submitted: 中文😀")
    try await edit("")
    let limitEditor = try editorForField(originalField)
    limitEditor.insertText("abcdefghijklmnopq", replacementRange: NSRange(location: 0, length: 0))
    try await wait("Limits: 1")
    guard originalField.stringValue.utf8.count <= 16 else { throw failure("UTF-8 limit exceeded") }
    try await press("Clear query", until: "Query: ")
    try await press("Make search read-only", until: "Search is read-only")
    guard try !field().isEditable else { throw failure("Read-only field is editable") }
    try await press("Make search editable", until: "Search is editable")
    try await press("Disable search input", until: "Search input disabled")
    guard try !field().isEnabled, try !control("Choose Inbox").enabled
    else { throw failure("Disabled search remained interactive") }
    try await press("Enable search input", until: "Search input enabled")
    try await press("Reject search close", until: "Close rejection enabled")
    try await press("Close search", until: "Close requests: 1")
    guard contains("Search: Open") else { throw failure("Rejected close removed search") }
    try await press("Accept search close", until: "Close rejection disabled")
    try await edit("Archive")
    try await press("Choose Archive", until: "Selected: 9")
    try await wait("Closed: 1")
    try await press("Open search", until: "Opened: 2")
    try await wait("Query: Archive") { (try? field().window) != nil }
    guard try field().stringValue == "Archive" else { throw failure("Query lost after reopening") }
    try await press("Close search", until: "Closed: 2")
    await session.close()
    print(
      "PASS: native search mode \(mode), revisioned input, suggestions, limits and presentation")
    fflush(stdout)
    exit(0)
  } catch {
    await session.close()
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
@MainActor private func editorForField(_ field: NSTextField) throws -> NSTextView {
  field.selectText(nil)
  guard let editor = field.currentEditor() as? NSTextView else {
    throw failure("Missing field editor")
  }
  return editor
}
private func failure(_ message: String) -> NSError {
  NSError(domain: "SearchWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
