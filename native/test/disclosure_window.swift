import AppKit
import SwiftUI

@main struct DisclosureWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Disclosure Acceptance", id: "disclosure-acceptance") {
      BonsaiApplicationView(entrypoint: "native-disclosure", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 500)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 560)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing disclosure window") }
    func control(_ title: String) throws -> AccessibilityElement {
      guard
        let element = accessibilityElements(host).first(where: {
          $0.role == "AXDisclosureTriangle" && $0.label?.contains(title) == true
        })
      else {
        throw failure(
          "Missing disclosure \(title): \(accessibilityElements(host).compactMap { ($0.role ?? "") + ":" + ($0.label ?? "") }.joined(separator: ";"))"
        )
      }
      return element
    }
    func has(_ title: String) -> Bool {
      accessibilityElements(host).contains {
        $0.label == title || ($0.role == "AXStaticText" && $0.value == title)
      }
    }
    func settle(_ text: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil && has(text) { return }
      }
      throw failure("Missing displayed result: \(text)")
    }
    func press(_ title: String) throws {
      guard
        let element = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title
        }), element.press()
      else { throw failure("Cannot press \(title)") }
    }
    try await settle("Expanded: 1; actions: 0")
    guard try control("Item one").numericValue == 1,
      try control("Item two").numericValue == 0,
      !(try control("Unavailable").enabled)
    else { throw failure("Incorrect initial disclosure states") }
    guard !has("Act in two") else { throw failure("Collapsed body is accessible") }
    guard try control("Item two").press() else { throw failure("Cannot expand second item") }
    try await settle("Expanded: 1,2; actions: 0")
    try press("Act in two")
    try await settle("Expanded: 1,2; actions: 1")
    try press("Single expansion")
    try await settle("Expanded: 1; actions: 1")
    guard try control("Item two").press() else { throw failure("Cannot select second item") }
    try await settle("Expanded: 2; actions: 1")
    guard !has("Act in one") else { throw failure("Previous single-expanded body is accessible") }
    try press("Reject expansion")
    try await settle("Accept expansion")
    guard try control("Item one").press() else {
      throw failure("Cannot request rejected expansion")
    }
    try await settle("Expanded: 2; actions: 1")
    guard try control("Item one").numericValue == 0 else {
      throw failure("Rejected expansion remains optimistic")
    }
    try press("Accept expansion")
    try await settle("Reject expansion")
    window.setContentSize(CGSize(width: 360, height: 560))
    try press("Reverse disclosures")
    try await settle("Expanded: 2; actions: 1")
    guard try control("Item one").press() else { throw failure("Cannot expand after reorder") }
    try await settle("Expanded: 1; actions: 1")
    guard try control("Item one").press() else { throw failure("Cannot collapse current item") }
    try await settle("Expanded: ; actions: 1")
    guard !has("Act in one") else { throw failure("Explicitly collapsed body is accessible") }
    guard try control("Item one").press() else { throw failure("Cannot reopen current item") }
    try await settle("Expanded: 1; actions: 1")
    try press("Disable disclosures")
    try await settle("Enable disclosures")
    guard try !control("Item one").enabled else {
      throw failure("Disabled disclosure remains enabled")
    }
    guard
      let body = accessibilityElements(host).first(where: {
        $0.role == "AXButton" && $0.label == "Act in one"
      }), !body.enabled
    else { throw failure("Disabled disclosure body remains enabled") }
    try press("Enable disclosures")
    try await settle("Disable disclosures")
    try press("Act in one")
    try await settle("Expanded: 1; actions: 2")
    await session.close()
    print(
      "PASS: actual Gallery Disclosure native expand/collapse, single/multiple policy, rejection, disabled content and reordering at both widths"
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
    domain: "DisclosureWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
