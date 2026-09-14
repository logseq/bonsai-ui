import AppKit
import SwiftUI

@main private struct ComposerWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Message Composer", id: "composer") {
      BonsaiApplicationView(entrypoint: "native-composer-focus", session: session)
        .task { await verifyComposer(session) }
    }.defaultSize(width: 600, height: 700)
  }
}
@MainActor private func editors(_ root: NSView) -> [NativeEditingTextView] {
  if let editor = root as? NativeEditingTextView { return [editor] }
  return root.subviews.flatMap { editors($0) }
}
@MainActor private func verifyComposer(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing composer window") }
    func wait(_ label: String, _ condition: () -> Bool) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil && condition() { return }
      }
      throw failure("Timed out: \(label)")
    }
    func has(_ title: String) -> Bool {
      accessibilityElements(window).contains { $0.label == title || $0.value == title }
    }
    func press(_ title: String) throws {
      guard
        let element = accessibilityElements(window).first(where: {
          $0.role == "AXButton" && $0.label == title
        }), element.press()
      else { throw failure("Missing action: \(title)") }
    }
    try await wait("native editor") { session.displayedRevision > 0 && editors(host).count == 1 }
    let editor = editors(host)[0]
    try await wait("autofocus") { window.firstResponder === editor }
    let initialHeight = editor.enclosingScrollView!.frame.height
    let draft = (0..<10).map { "Line \($0)" }.joined(separator: "\n")
    editor.insertText(draft, replacementRange: NSRange(location: 0, length: 0))
    try await wait("observed multiline draft") { has("Observed draft: " + draft) }
    let expandedHeight = editor.enclosingScrollView!.frame.height
    guard expandedHeight > initialHeight * 3, expandedHeight <= initialHeight * 5 + 3 else {
      throw failure("Five-line height: \(initialHeight) -> \(expandedHeight)")
    }
    try press("Send")
    try await wait("exact native action") { has("Last action: 3:" + draft) }
    guard editor.string == draft else { throw failure("Send cleared the draft") }
    try press("Change composer layout")
    try await wait("changed line limit") {
      editor.enclosingScrollView!.frame.height < expandedHeight
    }
    guard editors(host).count == 1, editors(host)[0] === editor, editor.string == draft,
      editor.enclosingScrollView!.frame.height <= initialHeight * 3 + 3
    else {
      throw failure("Configuration replaced the editor or exceeded its new line limit")
    }
    try press("Collapse composer")
    try await wait("collapsed height and focus") {
      editor.enclosingScrollView!.frame.height <= initialHeight + 3
        && window.firstResponder !== editor
    }
    guard editor.string == draft, editors(host)[0] === editor else {
      throw failure("Collapse replaced draft ownership")
    }
    guard window.makeFirstResponder(editor) else { throw failure("Native editor rejected focus") }
    try await wait("focus re-expansion") {
      editor.enclosingScrollView!.frame.height > initialHeight * 2
    }
    editor.insertText(
      " \u{3000}\n", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    try await wait("whitespace actions") { has("Voice") && !has("Send") }
    try press("Attach")
    try await wait("untrimmed whitespace action") { has("Last action: 1: \u{3000}\n") }
    try press("Reset draft")
    try await wait("new keyed editor") {
      editors(host).count == 1 && editors(host)[0] !== editor && editors(host)[0].string.isEmpty
    }
    await session.close()
    guard editor.delegate == nil else {
      throw failure("Disposed composer retained its editor delegate")
    }
    print(
      "PASS: actual composer window preserves draft, autofocus, adaptive height, raw actions and native editor identity"
    )
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func failure(_ message: String) -> NSError {
  NSError(domain: "ComposerAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
