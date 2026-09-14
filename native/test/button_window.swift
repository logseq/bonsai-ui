import AppKit
import SwiftUI

@main struct ButtonWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Button Acceptance", id: "button-acceptance") {
      BonsaiApplicationView(entrypoint: "native-buttons", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 480)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 520)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing button window") }
    func has(_ title: String) -> Bool {
      accessibilityElements(host).contains {
        $0.label == title || ($0.role == "AXStaticText" && $0.value == title)
      }
    }
    func button(_ title: String) throws -> AccessibilityElement {
      guard
        let value = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title
        })
      else { throw failure("Missing native Button: \(title)") }
      return value
    }
    func settled(_ title: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil && has(title) { return }
      }
      throw failure("Missing displayed result: \(title)")
    }
    func press(_ title: String) throws {
      guard try button(title).press() else { throw failure("Cannot press \(title)") }
    }
    try await settled("Button actions: 0")
    var count = 0
    for width in [640.0, 360.0] {
      window.setContentSize(CGSize(width: width, height: 520))
      for size in ["Large", "Extra large", "Mini", "Small", "Regular"] {
        try press("Next control size")
        try await settled("Size: \(size)")
        for title in ["Automatic", "Bordered", "Prominent", "Refresh"] {
          try press(title)
          count += 1
          try await settled("Button actions: \(count)")
        }
      }
      try press("Disable buttons")
      try await settled("Enable buttons")
      for title in ["Automatic", "Bordered", "Prominent", "Refresh"] {
        guard try !button(title).enabled else { throw failure("Disabled Button remained enabled") }
        _ = try button(title).press()
      }
      try await settled("Button actions: \(count)")
      try press("Enable buttons")
      try await settled("Disable buttons")
    }
    await session.close()
    print(
      "PASS: actual Gallery buttons native actions retain labels and disable across five sizes at both widths"
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
  NSError(
    domain: "ButtonWindowAcceptance", code: 1,
    userInfo: [NSLocalizedDescriptionKey: text])
}
