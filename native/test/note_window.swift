import AppKit
import SwiftUI

@testable import BonsaiSwiftUI

@main struct NoteWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Bonsai Note", id: "note-acceptance") {
      BonsaiApplicationView(entrypoint: "note", session: session)
        .frame(minWidth: 320, minHeight: 500)
        .task { await verify() }
    }.defaultSize(width: 520, height: 860)
  }

  @MainActor private func verify() async {
    do {
      let window = try require(NSApp.windows.first { $0.contentView != nil }, "Missing window")
      let content = try require(window.contentView, "Missing content")
      func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
          if predicate() {
            try await settleAccessibility(content)
            return
          }
          try await Task.sleep(for: .milliseconds(50))
        }
        throw failure("Timed out waiting for Note")
      }
      func named(_ name: String, in node: RenderNodeState) -> Bool {
        if case .text(let text) = node.properties, text.value == name { return true }
        if case .semantics(let semantics) = node.properties, semantics.label == name { return true }
        return node.children.contains { named(name, in: $0) }
      }
      func button(_ name: String) throws -> RenderNodeState {
        try require(
          session.tree.nodes.values.first {
            if case .button = $0.properties { return named(name, in: $0) }
            return false
          }, "Missing button: \(name)")
      }
      func click(_ name: String) async throws {
        let revision = session.displayedRevision
        guard session.activate(try button(name)) else { throw failure("Rejected: \(name)") }
        try await wait { session.displayedRevision > revision }
      }
      try await wait { session.displayedRevision > 0 }
      window.setContentSize(NSSize(width: 520, height: 860))
      try await settleAccessibility(content)
      try capture(window, "macos-cornell")
      window.setContentSize(NSSize(width: 320, height: 700))
      try await settleAccessibility(content)
      try capture(window, "macos-narrow")
      for name in ["Templates", "Share preview", "Edit note"] {
        let node = try button(name)
        let registry = try require(node.layoutTarget.registry, "Detached button")
        let rect = try await registry.measure(node.layoutTarget, valid: { true })
        guard rect.width > 0, rect.height > 0, rect.minX >= -1, rect.maxX <= 321 else {
          throw failure("Clipped control: \(name), \(rect)")
        }
      }
      try await click("Edit note")
      try await wait { session.tree.nodes.values.contains { $0.fieldController != nil } }
      let field = try require(
        session.tree.nodes.values.compactMap { $0.fieldController?.field }
          .first { $0.window != nil }, "Missing title editor")
      field.selectText(nil)
      let editor = try require(field.currentEditor() as? NSTextView, "Missing focused editor")
      editor.insertText(
        "Shared defaults draft",
        replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      try await Task.sleep(for: .milliseconds(200))
      try await click("Done")
      guard session.tree.nodes.values.contains(where: { named("Shared defaults draft", in: $0) })
      else {
        throw failure("Editing lost the draft")
      }
      try capture(window, "macos-edited")
      try await click("Templates")
      try await wait {
        session.tree.nodes.values.compactMap { $0.fieldController?.field }.contains {
          $0.window != nil
        }
      }
      let search = try require(
        session.tree.nodes.values.compactMap { $0.fieldController?.field }
          .first { $0.window != nil }, "Missing search field")
      search.selectText(nil)
      let searchEditor = try require(search.currentEditor() as? NSTextView, "Search did not focus")
      searchEditor.insertText(
        "no matching template",
        replacementRange: NSRange(location: 0, length: searchEditor.string.utf16.count))
      try await wait { session.tree.nodes.values.contains { named("No templates found", in: $0) } }
      try await click("Clear search")
      try await click("Close templates")
      print("PASS: actual Note native window, narrow controls, editing and search")
      await session.close()
      exit(0)
    } catch {
      fputs("FAIL: \(error)\n", stderr)
      await session.close()
      exit(1)
    }
  }
}

private func failure(_ message: String) -> NSError {
  NSError(domain: "NoteWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
private func require<T>(_ value: T?, _ message: String) throws -> T {
  guard let value else { throw failure(message) }
  return value
}
@MainActor private func capture(_ window: NSWindow, _ name: String) throws {
  guard let directory = ProcessInfo.processInfo.environment["BONSAI_NOTE_CAPTURE_DIRECTORY"] else {
    return
  }
  let view = try require(window.contentView, "Missing content")
  view.layoutSubtreeIfNeeded()
  view.displayIfNeeded()
  let bitmap = try require(view.bitmapImageRepForCachingDisplay(in: view.bounds), "Missing bitmap")
  view.cacheDisplay(in: view.bounds, to: bitmap)
  let png = try require(bitmap.representation(using: .png, properties: [:]), "Missing PNG")
  let folder = URL(fileURLWithPath: directory)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  try png.write(to: folder.appendingPathComponent(name + ".png"))
}
