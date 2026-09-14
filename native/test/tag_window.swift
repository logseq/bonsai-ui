import AppKit
import SwiftUI

@main struct TagWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Tag Acceptance", id: "tag-acceptance") {
      BonsaiApplicationView(entrypoint: "native-tags", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 600)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 640)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing tag window") }
    var step = "initial presentation"
    func has(_ label: String) -> Bool {
      accessibilityElements(host).contains {
        $0.label == label || ($0.role == "AXStaticText" && $0.value == label)
      }
    }
    func element(_ label: String) throws -> AccessibilityElement {
      guard
        let value = accessibilityElements(host).first(where: {
          $0.label == label && ($0.role == "AXButton" || $0.numericValue != nil)
        })
      else { throw failure("Missing native control: \(label)") }
      return value
    }
    func settled(_ condition: () throws -> Bool) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil,
          session.tree.nodes.values.allSatisfy({ $0.booleanControlController?.pending == nil }),
          try condition()
        {
          return
        }
      }
      let details = accessibilityElements(host).map {
        "\($0.role ?? "?") label=\($0.label ?? "nil") value=\($0.value ?? "nil")"
      }.joined(separator: "\n")
      throw failure("Tag controls did not settle after \(step):\n\(details)")
    }
    func press(_ label: String) throws {
      step = label
      guard try element(label).press() else { throw failure("Cannot press \(label)") }
    }
    try await settled { has("Actions: 0") }
    guard !has("Remove Pinned") else { throw failure("Non-removable tag has a delete action") }
    for (index, width) in [640.0, 360.0].enumerated() {
      window.setContentSize(CGSize(width: width, height: 640))
      try await settleAccessibility(host)
      func frame(_ title: String) throws -> CGRect {
        let object = try element(title).object
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { throw failure("Missing native frame") }
        typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
      }
      let first = try frame("Work")
      let second = try frame("Personal")
      guard first.width > 0, second.width > 0,
        width == 640 ? abs(first.midY - second.midY) < 2 : abs(first.midY - second.midY) > 10
      else { throw failure("Tags failed to reflow at width \(width): \(first), \(second)") }
      try press("Assist")
      try await settled { has("Actions: \(index * 2 + 1)") }
      try press("Suggestion")
      try await settled { has("Actions: \(index * 2 + 2)") }
      try press("Work")
      try await settled { try element("Work").numericValue == 1 }
      try press("Ignore tag changes")
      try await settled { has("Accept tag changes") }
      try press("Work")
      guard
        session.tree.nodes.values.contains(where: { $0.booleanControlController?.pending != nil })
      else { throw failure("Native selection did not enqueue its request") }
      try await settled { try element("Work").numericValue == 1 }
      try press("Remove Personal")
      try await settled { has("Personal") && has("Remove Personal") }
      try press("Accept tag changes")
      try await settled { has("Ignore tag changes") }
      try press("Disable tags")
      try await settled { has("Enable tags") }
      for label in ["Assist", "Suggestion", "Filter", "Suggested", "Work", "Remove Work"] {
        guard try !element(label).enabled else {
          throw failure("Disabled tag action remained enabled")
        }
        _ = try element(label).press()
      }
      try await settled { try element("Work").numericValue == 1 }
      try press("Enable tags")
      try await settled { has("Disable tags") }
      try press("Remove Personal")
      try await settled { !has("Personal") && !has("Remove Personal") }
      guard try element("Work").numericValue == 1, has("Actions: \(index * 2 + 2)")
      else { throw failure("Removing a tag changed another control") }
      try press("Restore tags")
      try await settled { try has("Personal") && element("Work").numericValue == 0 }
    }
    await session.close()
    print("PASS: actual Gallery tags native actions select, remove and disable at both widths")
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
    domain: "TagWindowAcceptance", code: 1,
    userInfo: [NSLocalizedDescriptionKey: text])
}
