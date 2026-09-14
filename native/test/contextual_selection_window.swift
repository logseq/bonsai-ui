import AppKit
import SwiftUI

@main struct ContextualSelectionAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Contextual selection", id: "contextual-selection") {
      BonsaiApplicationView(entrypoint: "native-contextual-selection", session: session)
        .frame(minWidth: 640, minHeight: 500)
        .task { await verify(session) }
    }.defaultSize(width: 900, height: 600)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing selection window") }
    func element(_ label: String) throws -> AccessibilityElement {
      let controls =
        (window.toolbar?.items.compactMap(\.view).flatMap {
          accessibilityElements($0)
        } ?? []) + accessibilityElements(window)
      guard
        let value = controls.first(where: {
          $0.label == label && ($0.role == "AXButton" || $0.numericValue != nil)
        })
      else { throw failure("Missing native control: \(label)") }
      return value
    }
    func text(_ expected: String) -> Bool {
      accessibilityElements(window).contains { $0.label == expected || $0.value == expected }
    }
    func settle(_ expected: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil,
          session.tree.nodes.values.allSatisfy({ $0.booleanControlController?.pending == nil }),
          text(expected)
        {
          return
        }
      }
      throw failure(
        "Missing state: \(expected); labels: \(accessibilityElements(window).compactMap { $0.label ?? $0.value })"
      )
    }
    func press(_ title: String, expected: String) async throws {
      guard try element(title).press() else { throw failure("Cannot press \(title)") }
      try await settle(expected)
    }
    try await settle("Selected IDs: None")
    for width in [900.0, 640.0] {
      window.setContentSize(CGSize(width: width, height: 600))
      try await settleAccessibility(host)
      guard try !element("Unavailable item").enabled else { throw failure("Disabled item enabled") }
      try await press("First item", expected: "Selected IDs: -7")
      guard try element("First item").numericValue == 1 else {
        throw failure("First item not checked")
      }
      guard window.toolbar != nil else {
        throw failure("Selection commands have no native toolbar")
      }
      try await press("Select all items", expected: "Selected IDs: -7,9")
      guard try element("Second item").numericValue == 1 else {
        throw failure("Select all missed second item")
      }
      try await press("Clear selection", expected: "Selected IDs: None")
      guard !text("Archive selected") else {
        throw failure("Contextual action remained while idle")
      }
      try await press("First item", expected: "Selected IDs: -7")
      try await press("Reject selection changes", expected: "Accept selection changes")
      guard try element("Second item").press() else {
        throw failure("Cannot request rejected selection")
      }
      try await settle("Selected IDs: -7")
      guard try element("Second item").numericValue == 0 else {
        throw failure("Rejected selection remained checked")
      }
      try await press("Accept selection changes", expected: "Reject selection changes")
      try await press("Reverse items", expected: "Selected IDs: -7")
      try await press("Disable selection", expected: "Enable selection")
      guard try !element("First item").enabled,
        try !element("Archive selected").enabled
      else { throw failure("Disabled selection still interactive") }
      try await press("Enable selection", expected: "Disable selection")
      try await press("Archive selected", expected: "Archived IDs: -7")
      guard !text("First item") else { throw failure("Archived item retained") }
      try await press("Reset items", expected: "Archived IDs: None")
    }
    await session.close()
    print(
      "PASS: native contextual selection, select-all, rejection and batch actions at both widths")
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
    domain: "ContextualSelectionAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
