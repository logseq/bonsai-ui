import AppKit
import SwiftUI

@main struct ClockWindowAcceptance: App {
  var body: some Scene {
    Window("Clock Acceptance", id: "clock-acceptance") {
      BonsaiApplicationView(entrypoint: "clock")
        .frame(minWidth: 520, minHeight: 420)
        .task { await verify() }
    }.defaultSize(width: 720, height: 800)
  }
}

@MainActor private func verify() async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing Clock window") }
    func waitText(_ prefix: String, excluding: String? = nil) async throws -> String {
      for _ in 0..<80 {
        try await settleAccessibility(host)
        if let text = accessibilityElements(host).compactMap({ $0.value ?? $0.label })
          .first(where: { $0.hasPrefix(prefix) && (excluding == nil || !$0.contains(excluding!)) })
        {
          return text
        }
      }
      throw failure(
        "Missing text: \(prefix); elements: \(accessibilityElements(host).map { ($0.role ?? "-", $0.value ?? $0.label ?? "-") })"
      )
    }
    func press(_ title: String) throws {
      guard
        let button = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title && $0.enabled
        }), button.press()
      else { throw failure("Cannot press \(title)") }
    }
    let initialTime = try await waitText("Exact now:")
    try press("Sample now")
    _ = try await waitText("Manual sample:", excluding: "Not sampled")
    try press("Wait for frame boundaries")
    _ = try await waitText("Before display: Completed")
    _ = try await waitText("After display: Completed")
    try press("Sleep 3s")
    _ = try await waitText("Relative sleep: Waiting")
    _ = try await waitText("Relative sleep: Completed")
    guard try await waitText("Exact now:") != initialTime else {
      throw failure("Logical time did not advance")
    }
    print("PASS: actual Clock native window advances timers and presentation waits through OCaml")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func failure(_ text: String) -> NSError {
  NSError(domain: "ClockWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
