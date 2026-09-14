import AppKit
import SwiftUI

@main struct NetworkWindowAcceptance: App {
  var body: some Scene {
    Window("Network Acceptance", id: "network-acceptance") {
      BonsaiApplicationView(entrypoint: "network-loopback")
        .frame(minWidth: 360, minHeight: 500)
        .task { await verify() }
    }.defaultSize(width: 680, height: 900)
  }
}

@MainActor private func verify() async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing network window") }
    func waitText(_ text: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if accessibilityElements(host).contains(where: { $0.value == text || $0.label == text }) {
          return
        }
      }
      throw failure(
        "Missing \(text): \(accessibilityElements(host).map { ($0.role ?? "-", $0.value ?? $0.label ?? "-") })"
      )
    }
    func button(_ title: String) throws -> AccessibilityElement {
      guard
        let button = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title
        })
      else { throw failure("Missing button \(title)") }
      return button
    }
    func press(_ title: String) throws {
      let control = try button(title)
      guard control.enabled, control.press() else { throw failure("Cannot press \(title)") }
    }
    func fields(_ view: NSView) -> [NSTextField] {
      if let field = view as? NSTextField { return [field] }
      return view.subviews.flatMap(fields)
    }
    try await waitText("HTTPS: Idle")
    try await waitText("WebSocket: Idle")
    guard let input = fields(host).first(where: { $0.accessibilityLabel() == "WebSocket message" }),
      !input.isEnabled, !(try button("Send").enabled), !(try button("Cancel").enabled)
    else {
      throw failure(
        "Initial input availability is incorrect: fields=\(fields(host).map { ($0.accessibilityLabel() ?? "-", $0.isEnabled, $0.frame) }); controls=\(accessibilityElements(host).filter { $0.role == "AXButton" }.map { ($0.label ?? "-", $0.enabled) })"
      )
    }
    try press("Run HTTPS GET")
    try await waitText("HTTPS: Complete")
    try await waitText("Status: 200")
    try await waitText("SwiftUI loopback HTTPS")
    try press("Run HTTPS GET")
    try await waitText("HTTPS: Running")
    guard !(try button("Run HTTPS GET").enabled) else { throw failure("Duplicate GET allowed") }
    guard let marker = ProcessInfo.processInfo.environment["BONSAI_NATIVE_NETWORK_REQUEST_MARKER"]
    else {
      throw failure("Missing request observation path")
    }
    for _ in 0..<80 {
      if (try? String(contentsOfFile: marker, encoding: .utf8)) == "2" { break }
      try await settleAccessibility(host)
    }
    guard (try? String(contentsOfFile: marker, encoding: .utf8)) == "2" else {
      throw failure("Second HTTPS request did not reach the TLS server")
    }
    try press("Cancel")
    try await waitText("HTTPS: Cancelled")
    try press("Run HTTPS GET")
    try await waitText("HTTPS: Failed")
    try press("Connect")
    try await waitText("WebSocket: Connected")
    guard input.isEnabled else { throw failure("Connected input remains disabled") }
    input.selectText(nil)
    guard let editor = input.currentEditor() as? NSTextView else {
      throw failure("Missing native field editor")
    }
    let message = "SwiftUI 本地😀"
    editor.insertText(
      message, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    for _ in 0..<40 {
      try await settleAccessibility(host)
      if try button("Send").enabled { break }
    }
    try press("Send")
    try await waitText("Message: Echo: \(message)")
    guard fields(host).contains(where: { $0 === input }), input.stringValue == message else {
      throw failure("Network updates replaced the field or draft")
    }
    try press("Disconnect")
    try await waitText("WebSocket: Closed")
    guard !input.isEnabled, !(try button("Send").enabled) else {
      throw failure("Disconnected input remains enabled")
    }
    window.setContentSize(CGSize(width: 360, height: 900))
    try await settleAccessibility(host)
    guard input.bounds.width >= 160 else { throw failure("Narrow network field is unusable") }
    print(
      "PASS: actual Network window completes TLS HTTP, cancellation, failure and Unicode WSS echo through OCaml"
    )
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func failure(_ text: String) -> NSError {
  NSError(domain: "NetworkWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
