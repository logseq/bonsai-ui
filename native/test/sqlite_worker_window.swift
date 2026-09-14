import AppKit
import SwiftUI

@main struct SQLiteWorkerWindowAcceptance: App {
  @State private var session = BonsaiSession()
  private let payload = try! SQLiteWorkerStartup.prepare(
    directory: URL(fileURLWithPath: ProcessInfo.processInfo.environment["BONSAI_SQLITE_DIRECTORY"]!)
  )
  var body: some Scene {
    Window("SQLite Worker Acceptance", id: "sqlite-worker-acceptance") {
      BonsaiApplicationView(entrypoint: "sqlite_worker", payload: payload, session: session)
        .frame(minWidth: 360, minHeight: 500)
        .task { await verify(session) }
    }.defaultSize(width: 680, height: 1000)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else {
      throw failure("Missing SQLite Worker window")
    }
    func waitText(_ text: String, prefix: Bool = false) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if accessibilityElements(host).contains(where: {
          let value = $0.value ?? $0.label ?? ""
          return prefix ? value.hasPrefix(text) : value == text
        }) {
          return
        }
      }
      throw failure(
        "Missing \(text): \(accessibilityElements(host).map { $0.value ?? $0.label ?? "-" })")
    }
    func button(_ title: String) throws -> AccessibilityElement {
      guard
        let button = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title
        })
      else {
        throw failure("Missing button \(title)")
      }
      return button
    }
    func press(_ title: String) throws {
      let button = try button(title)
      guard button.enabled && button.press() else { throw failure("Cannot press \(title)") }
    }
    func fields(_ view: NSView) -> [NSTextField] {
      if let field = view as? NSTextField { return [field] }
      return view.subviews.flatMap(fields)
    }
    try await waitText("Ready")
    try await waitText("Worker startup timings")
    guard let input = fields(host).first(where: { $0.accessibilityLabel() == "Todo title" }) else {
      throw failure("Missing Todo title field")
    }
    let title = "Persisted 本地😀"
    let phase = ProcessInfo.processInfo.environment["BONSAI_SQLITE_PHASE"]!
    if phase == "write" {
      try await waitText("0 open · 0 completed")
      input.selectText(nil)
      guard let editor = input.currentEditor() as? NSTextView else {
        throw failure("Missing native editor")
      }
      editor.insertText(
        title, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      try await settleAccessibility(host)
      try press("Add")
      try await waitText(title)
      try await waitText("1 open · 0 completed")
      guard fields(host).contains(where: { $0 === input }), input.stringValue.isEmpty else {
        throw failure("Add did not retain and clear the native editor")
      }
      try press("Complete")
      try await waitText("0 open · 1 completed")
      try press("Refresh")
      try await waitText("Reopen")
      try press("Read demo file")
      try await waitText("Demo file error:", prefix: true)
      try press("Write 4 MiB demo file")
      try await waitText("Wrote 4194304 bytes")
      try press("Read demo file")
      try await waitText("Read 4194304 bytes")
      guard !(try button("Cancel file operation").enabled) else {
        throw failure("Idle cancellation is enabled")
      }
    } else {
      try await waitText(title)
      try await waitText("0 open · 1 completed")
      try press("Reopen")
      try await waitText("1 open · 0 completed")
      try press("Read demo file")
      try await waitText("Read 4194304 bytes")
    }
    window.setContentSize(CGSize(width: 360, height: 1000))
    try await settleAccessibility(host)
    guard input.bounds.width >= 200 else {
      throw failure("Narrow editor is unusable: \(input.bounds)")
    }
    await session.close()
    guard input.delegate == nil else {
      throw failure("Closed SQLite runtime retained its field delegate")
    }
    print("PASS: actual SQLite Worker window \(phase) preserves Unicode todos and file data")
    fflush(stdout)
    exit(0)
  } catch {
    await session.close()
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func failure(_ message: String) -> NSError {
  NSError(
    domain: "SQLiteWorkerWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
