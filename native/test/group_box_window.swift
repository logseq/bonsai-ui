import AppKit
import SwiftUI

@main struct GroupBoxWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("GroupBox Acceptance", id: "group-box-acceptance") {
      BonsaiApplicationView(entrypoint: "native-groups", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 500)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 560)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing GroupBox window") }
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
    try await settle("Card: none; actions: 0")
    for (index, width) in [640.0, 360.0].enumerated() {
      window.setContentSize(CGSize(width: width, height: 560))
      let count = index * 2
      try await press("Select one", result: "Card: 1; actions: \(count)")
      try await press("Act in one", result: "Card: 1; actions: \(count + 1)")
      try await press("Open two", result: "Card: 2; actions: \(count + 1)")
      try await press("Hide group label", result: "Show group label")
      try await press("Reverse cards", result: "Card: 2; actions: \(count + 1)")
      try await press("Act in one", result: "Card: 2; actions: \(count + 2)")
      try await press("Show group label", result: "Hide group label")
      try await press("Disable card actions", result: "Enable card actions")
      for title in ["Select one", "Act in one", "Open two"] {
        guard try !button(title).enabled else { throw failure("Enabled disabled action: \(title)") }
      }
      try await press("Enable card actions", result: "Disable card actions")
    }
    await session.close()
    print(
      "PASS: actual Gallery GroupBox independent actions, disabled controls, label changes and reordering at both widths"
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
  NSError(domain: "GroupBoxWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
