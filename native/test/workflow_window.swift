import AppKit
import SwiftUI

@main struct WorkflowWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Workflow Acceptance", id: "workflow-acceptance") {
      BonsaiApplicationView(entrypoint: "native-workflow", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 640)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 740)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing workflow window") }
    func has(_ title: String) -> Bool {
      accessibilityElements(host).contains {
        $0.label == title || ($0.role == "AXStaticText" && $0.value == title)
      }
    }
    func settled(_ title: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil && has(title) { return }
      }
      throw failure("Missing displayed workflow result: \(title)")
    }
    func control(_ title: String) throws -> AccessibilityElement {
      guard
        let element = accessibilityElements(host).first(where: {
          $0.role == "AXButton"
            && ($0.label == title
              || ($0.label?.contains(title) == true && $0.label?.hasPrefix("Act in") != true))
        })
      else { throw failure("Missing control \(title)") }
      return element
    }
    func press(_ title: String) throws {
      guard try control(title).press() else { throw failure("Cannot press \(title)") }
    }
    try await settled("Workflow: 1; actions: 0")
    for (title, state) in [
      ("Edit", "Editing"), ("Review", "Complete"),
      ("Fix", "Error"), ("Locked", "Disabled"), ("Finish", "Pending"),
    ] {
      let element = try control(title)
      guard element.enabled == (title != "Locked"), element.value == state,
        element.selected == (title == "Edit")
      else {
        throw failure(
          "Incorrect native workflow state for \(title): \(element.value ?? "nil"), selected=\(element.selected), enabled=\(element.enabled)"
        )
      }
    }
    for width in [640, 360] {
      window.setContentSize(CGSize(width: width, height: 740))
      try await settleAccessibility(host)
      guard !has("Act in Review") else { throw failure("Inactive step is accessible") }
      try press("Continue")
      try await settled("Act in Review")
      guard try control("Review").selected, !(try control("Edit").selected) else {
        throw failure("Native selection traits did not follow the current step")
      }
      guard !has("Act in Edit") else { throw failure("Previous step remains accessible") }
      try press("Back")
      try await settled("Act in Edit")
      try press("Reverse workflow")
      try await settled("Act in Edit")
      try press("Fix")
      try await settled("Act in Fix")
      try press("Change workflow layout")
      try await settled("Act in Fix")
      try press("Finish")
      try await settled("Act in Finish")
      try press("Back")
      try await settled("Act in Edit")
    }
    await session.close()
    print(
      "PASS: actual Gallery Workflow native selection, next/back, state markers, hidden content, reorder and layouts at both widths"
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
  NSError(domain: "WorkflowWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
