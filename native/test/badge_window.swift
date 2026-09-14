import AppKit
import SwiftUI

@main struct BadgeWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Badge Acceptance", id: "badge-acceptance") {
      BonsaiApplicationView(entrypoint: "native-badges", session: session)
        .padding(32).frame(minWidth: 360, minHeight: 540)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 600)
  }
}
@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing badge window") }
    func button(_ title: String) throws -> AccessibilityElement {
      guard
        let element = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title
        })
      else { throw failure("Missing button: \(title)") }
      return element
    }
    func settle(_ text: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil
          && accessibilityElements(host).contains(where: {
            $0.label == text || ($0.role == "AXStaticText" && $0.value == text)
          })
        {
          return
        }
      }
      throw failure("Missing displayed result: \(text)")
    }
    func press(_ title: String, result: String) async throws {
      guard try button(title).press() else { throw failure("Cannot press: \(title)") }
      try await settle(result)
    }
    try await settle("Badge actions: 0")
    for (index, width) in [640.0, 360.0].enumerated() {
      window.setContentSize(CGSize(width: width, height: 600))
      let status = "Badge actions: \(index * 2)"
      for (control, value) in [
        ("Maximum badge", "4611686018427387903"), ("Dot badge", "Unread"), ("Zero badge", "0"),
        ("Increment badge", "1"),
      ] {
        try await press(control, result: status)
        guard try button("Open notifications").value == value else {
          throw failure("Lost exact accessible count: \(value)")
        }
      }
      for _ in 0..<3 { try await press("Move badge", result: status) }
      try await press("Hide badge", result: "Show badge")
      try await press("Open notifications", result: "Badge actions: \(index * 2 + 1)")
      try await press("Disable content", result: "Enable content")
      guard try !button("Open notifications").enabled else {
        throw failure("Disabled content remains enabled")
      }
      try await press("Show badge", result: "Hide badge")
      try await press("Enable content", result: "Disable content")
      try await press("Open notifications", result: "Badge actions: \(index * 2 + 2)")
    }
    await session.close()
    print(
      "PASS: actual Gallery Badge exact counts, dot/zero, visibility, alignment and disabled content at both widths"
    )
    fflush(stdout)
    exit(0)
  } catch {
    await session.close()
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func failure(_ text: String) -> NSError {
  NSError(domain: "BadgeWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
