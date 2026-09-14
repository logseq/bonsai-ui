import AppKit
import SwiftUI

@main struct MultipleSelectionWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Multiple Selection Acceptance", id: "multiple-selection-acceptance") {
      BonsaiApplicationView(entrypoint: "native-multiple-selection", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 420)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 460)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing multiple-selection window") }
    func element(_ label: String) throws -> AccessibilityElement {
      guard
        let value = accessibilityElements(host).first(where: {
          $0.label == label && ($0.role == "AXButton" || $0.numericValue != nil)
        })
      else { throw failure("Missing native control: \(label)") }
      return value
    }
    func settled(_ first: Bool, _ second: Bool) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil,
          session.tree.nodes.values.filter({ $0.booleanControlController != nil }).count == 6,
          session.tree.nodes.values.allSatisfy({ $0.booleanControlController?.pending == nil }),
          try element("Buttons First").numericValue == (first ? 1 : 0),
          try element("Checkboxes First").numericValue == (first ? 1 : 0),
          try element("Buttons Second").numericValue == (second ? 1 : 0),
          try element("Checkboxes Second").numericValue == (second ? 1 : 0)
        {
          return
        }
      }
      throw failure("Native selected states did not settle")
    }
    func press(_ label: String) throws {
      guard try element(label).press() else { throw failure("Cannot press \(label)") }
    }
    func mode(_ label: String, next: String) async throws {
      try press(label)
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil,
          accessibilityElements(host).contains(where: { $0.label == next })
        {
          return
        }
      }
      throw failure("Mode did not change to \(next)")
    }
    try await settled(false, false)
    for width in [640.0, 360.0] {
      window.setContentSize(CGSize(width: width, height: 460))
      try await settleAccessibility(host)
      try press("Buttons First")
      try await settled(true, false)
      try press("Buttons Second")
      try await settled(true, true)
      try press("Checkboxes First")
      try await settled(false, true)
      try await mode("Ignore choices", next: "Accept choices")
      for title in ["Buttons First", "Checkboxes Second"] {
        try press(title)
        guard
          session.tree.nodes.values.contains(where: { $0.booleanControlController?.pending != nil })
        else { throw failure("Native toggle did not enqueue its request") }
        try await settled(false, true)
      }
      try await mode("Accept choices", next: "Ignore choices")
      try await mode("Disable choices", next: "Enable choices")
      for title in [
        "Buttons First", "Checkboxes Second", "Buttons Disabled", "Checkboxes Disabled",
      ] {
        guard try !element(title).enabled else { throw failure("Disabled toggle remained enabled") }
        _ = try element(title).press()
      }
      try await settled(false, true)
      try await mode("Enable choices", next: "Disable choices")
      guard try !element("Buttons Disabled").enabled, try !element("Checkboxes Disabled").enabled
      else { throw failure("Unavailable option became enabled") }
      try press("Clear choices")
      try await settled(false, false)
    }
    await session.close()
    print(
      "PASS: actual Gallery multiple selection native toggles accept, reject and disable at both widths"
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
    domain: "MultipleSelectionWindowAcceptance", code: 1,
    userInfo: [NSLocalizedDescriptionKey: text])
}
