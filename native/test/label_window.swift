import AppKit
import SwiftUI

@main struct LabelWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Label Acceptance", id: "label-acceptance") {
      BonsaiApplicationView(entrypoint: "native-labels", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 500)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 560)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing label window") }
    func button(_ title: String) throws -> AccessibilityElement {
      guard
        let element = accessibilityElements(host).first(where: {
          $0.role == "AXButton"
            && ($0.label == title
              || (["Inbox", "Archive"].contains(title) && $0.label?.contains(title) == true
                && $0.label?.contains("Info for") != true))
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
    try await settle("Row: none; opens: 0; info: 0")
    for (index, width) in [640.0, 360.0].enumerated() {
      window.setContentSize(CGSize(width: width, height: 560))
      try await settleAccessibility(host)
      func frame(_ title: String) throws -> CGRect {
        let object = try button(title).object
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { throw failure("Missing native frame") }
        typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
      }
      let primary = try frame("Inbox")
      let accessory = try frame("Info for Inbox")
      guard primary.width >= width - accessory.width - 80,
        primary.maxX <= accessory.minX + 1
      else {
        throw failure(
          "Row action did not fill its available width independently: \(primary), \(accessory)")
      }
      let count = index * 2
      try await press("Inbox", result: "Row: 1; opens: \(count + 1); info: \(count)")
      guard try button("Inbox").selected, !(try button("Archive").selected) else {
        throw failure("Missing native selected state")
      }
      guard try button("Inbox").label?.contains("Unread messages") == true,
        try button("Inbox").label?.contains("Mailboxes") == true
      else { throw failure("Missing composed native title content") }
      try await press("Info for Inbox", result: "Row: 1; opens: \(count + 1); info: \(count + 1)")
      try await press("Disable rows", result: "Enable rows")
      guard try !button("Inbox").enabled, try button("Info for Inbox").enabled else {
        throw failure("Incorrect independent enabled state")
      }
      try await press("Info for Inbox", result: "Row: 1; opens: \(count + 1); info: \(count + 2)")
      try await press("Hide row details", result: "Show row details")
      guard !accessibilityElements(host).contains(where: { $0.label == "Info for Inbox" }) else {
        throw failure("Removed accessory remains accessible")
      }
      try await press("Reverse rows", result: "Row: 1; opens: \(count + 1); info: \(count + 2)")
      try await press("Show row details", result: "Hide row details")
      try await press("Enable rows", result: "Disable rows")
      try await press("Archive", result: "Row: 2; opens: \(count + 2); info: \(count + 2)")
      guard try button("Archive").selected, !(try button("Inbox").selected) else {
        throw failure("Stale native selected state after reorder")
      }
    }
    await session.close()
    print(
      "PASS: actual Gallery Label rows expose composed titles, selection, independent accessories, disabled state and reorder at both widths"
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
  NSError(domain: "LabelWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
