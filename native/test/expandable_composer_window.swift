import AppKit
import SwiftUI

@main private struct ExpandableComposerWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Expandable Message Composer", id: "composer") {
      BonsaiApplicationView(entrypoint: "native-expandable-composer", session: session)
        .task { await verifyComposer(session) }
    }.defaultSize(width: 700, height: 700)
  }
}
@MainActor private func editors(_ view: NSView) -> [NativeEditingTextView] {
  if let editor = view as? NativeEditingTextView { return [editor] }
  return view.subviews.flatMap { editors($0) }
}
@MainActor private func verifyComposer(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing app window") }
    func wait(_ label: String, _ condition: () -> Bool) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if let sheet = window.sheets.first?.contentView { try await settleAccessibility(sheet) }
        if session.ticket == nil && condition() { return }
      }
      throw failure("Timed out: \(label)")
    }
    func press(_ title: String, sheet: Bool = false) throws {
      let target = sheet ? window.sheets.first : window
      guard let target,
        let action = accessibilityElements(target).first(where: {
          $0.role == "AXButton" && $0.label == title
        }), action.press()
      else { throw failure("Missing action: \(title)") }
    }
    func contains(_ text: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let value) = $0.properties { return value.value == text }
        return false
      }
    }
    try await wait("launcher") { session.displayedRevision > 0 }
    try press("Open composer")
    try await wait("sheet editor") {
      window.sheets.first?.contentView.map { editors($0).count == 1 } == true
    }
    let sheet = window.sheets[0]
    let editor = editors(sheet.contentView!)[0]
    try await wait("sheet autofocus") { sheet.firstResponder === editor }
    let lineHeight = editor.enclosingScrollView!.frame.height
    let draft = (0..<10).map { "Line \($0)" }.joined(separator: "\n")
    editor.insertText(draft, replacementRange: NSRange(location: 0, length: 0))
    try await wait("draft event") { contains("Observed draft: " + draft) }
    let expandedHeight = editor.enclosingScrollView!.frame.height
    guard expandedHeight > lineHeight * 3, expandedHeight <= lineHeight * 5 + 3 else {
      throw failure("Five-line limit was not respected")
    }
    editor.setSelectedRange(NSRange(location: 2, length: 3))
    let selection = editor.selectedRange()
    try press("Change launcher", sheet: true)
    try await wait("compact launcher configuration") {
      editor.accessibilityLabel() == "Compact launcher draft"
        && editor.enclosingScrollView!.frame.height < expandedHeight
    }
    guard editor.selectedRange() == selection,
      editors(sheet.contentView!).count == 1, editors(sheet.contentView!)[0] === editor
    else {
      throw failure("Configuration replaced editor identity or selection")
    }
    sheet.cancelOperation(nil)
    try await wait("native Escape dismissal") { window.sheets.isEmpty }
    try press("Open composer")
    try await wait("reopened autofocus") {
      window.sheets.first?.firstResponder === editor
    }
    guard editor.string == draft, editor.selectedRange() == selection else {
      throw failure("Reopening lost the draft or selection")
    }
    try press("Send", sheet: true)
    try await wait("raw action") { contains("Last action: 3:" + draft) }
    try press("Close", sheet: true)
    try await wait("close button") { window.sheets.isEmpty }
    try press("Background action")
    try await wait("background restored") { contains("Background: 1") }
    await session.close()
    guard editor.delegate == nil else { throw failure("Editor delegate survived closure") }
    print(
      "PASS: actual expandable composer window retains draft, selection, native autofocus, line limits and Escape dismissal"
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
  NSError(
    domain: "ExpandableComposerAcceptance", code: 1,
    userInfo: [NSLocalizedDescriptionKey: message])
}
