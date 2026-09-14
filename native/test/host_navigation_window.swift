import AppKit
import SwiftUI

@main struct HostNavigationWindowAcceptance: App {
  private let pasteboard: NSPasteboard
  @State private var session: BonsaiSession
  init() {
    let pasteboard = NSPasteboard.withUniqueName()
    self.pasteboard = pasteboard
    _session = State(
      initialValue: BonsaiSession(hostService: NativeHostService(pasteboard: pasteboard)))
  }
  var body: some Scene {
    Window("Host Navigation Acceptance", id: "host-navigation-acceptance") {
      BonsaiApplicationView(entrypoint: "host_navigation", session: session)
        .frame(minWidth: 360, minHeight: 360)
        .task { await verify(session, pasteboard: pasteboard) }
    }.defaultSize(width: 640, height: 520)
  }
}

@MainActor private func verify(_ session: BonsaiSession, pasteboard: NSPasteboard) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing Host Navigation window") }
    func waitText(_ text: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if accessibilityElements(host).contains(where: { $0.value == text || $0.label == text }) {
          return
        }
      }
      throw failure("Missing text: \(text)")
    }
    func press(_ title: String, toolbar: Bool = false) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        let elements =
          toolbar
          ? (window.toolbar?.items.compactMap(\.view).flatMap { accessibilityElements($0) } ?? [])
          : accessibilityElements(host)
        if let control = elements.first(where: {
          $0.role == "AXButton" && $0.enabled && ($0.label == title || $0.help == title)
        }), control.press() {
          return
        }
      }
      throw failure("Cannot press \(title)")
    }
    try await waitText("Clipboard not read")
    pasteboard.setString("Native navigation 本地😀", forType: .string)
    try await press("Read clipboard")
    try await waitText("Native navigation 本地😀")
    for width in [640.0, 360.0] {
      window.setContentSize(CGSize(width: width, height: 520))
      try await press("Open settings")
      try await waitText("Overlay owned by OCaml")
      try await waitText("Settings content owned by OCaml")
      try await press("Close settings")
      try await waitText("Native navigation 本地😀")
      try await press("Open settings")
      try await waitText("Settings content owned by OCaml")
      try await press("Back", toolbar: true)
      try await waitText("Native navigation 本地😀")
      for _ in 0..<100 {
        if session.tree.root?.children.count == 1 && session.ticket == nil { break }
        try await settleAccessibility(host)
      }
      guard session.tree.root?.navigationController?.path.isEmpty == true,
        session.tree.root?.children.count == 1, session.ticket == nil
      else {
        throw failure("System Back did not update the OCaml path")
      }
    }
    pasteboard.clearContents()
    pasteboard.setString(
      String(repeating: "x", count: ProtocolLimits.maxStringBytes + 1),
      forType: .string)
    try await press("Read clipboard")
    try await waitText("Clipboard request failed")
    await session.close()
    pasteboard.releaseGlobally()
    print(
      "PASS: actual Host Navigation native clipboard, Settings, Close and system Back at both widths"
    )
    fflush(stdout)
    exit(0)
  } catch {
    await session.close()
    pasteboard.releaseGlobally()
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}

private func failure(_ text: String) -> NSError {
  NSError(
    domain: "HostNavigationWindowAcceptance", code: 1,
    userInfo: [NSLocalizedDescriptionKey: text])
}
