import AppKit
import SwiftUI

@main struct HoverWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Hover Acceptance", id: "hover-acceptance") {
      BonsaiApplicationView(entrypoint: "native-hover", session: session)
        .padding(24).frame(minWidth: 500, minHeight: 580)
        .task { await verify(session) }
    }.defaultSize(width: 560, height: 620)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing hover window") }
    func named(_ title: String, _ node: RenderNodeState) -> Bool {
      if case .text(let text) = node.properties, text.value == title { return true }
      return node.children.contains { named(title, $0) }
    }
    func front() throws -> RenderNodeState {
      guard
        let node = session.tree.nodes.values.first(where: {
          $0.hoverController != nil && named("Front hover", $0) && !named("Inner action", $0)
        })
      else { throw failure("Missing front hover region") }
      return node
    }
    func count() -> Int? {
      for node in session.tree.nodes.values {
        if case .text(let text) = node.properties, text.value.hasPrefix("Hover events: ") {
          return Int(text.value.dropFirst("Hover events: ".count))
        }
      }
      return nil
    }
    func settle(_ expected: Int) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil, count() == expected,
          accessibilityElements(host).contains(where: {
            $0.label == "Hover events: \(expected)" || $0.value == "Hover events: \(expected)"
          })
        {
          return
        }
      }
      throw failure("Expected \(expected) hover events, got \(String(describing: count()))")
    }
    func press(_ title: String, count: Int) async throws {
      guard
        let button = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title
        }), button.press()
      else { throw failure("Cannot activate \(title)") }
      try await settle(count)
    }
    try await settle(0)
    guard session.tree.activeHoverWindowCount == 1 else {
      throw failure("Nested hover regions did not share one window source")
    }
    session.isActive = false
    guard session.tree.activeHoverWindowCount == 0 else {
      throw failure("Inactive session retained its window source until a later layout")
    }
    session.isActive = true
    try await settle(0)
    guard session.tree.activeHoverWindowCount == 1 else {
      throw failure("Reactivated session did not create its window source")
    }
    let initialFront = try front()
    guard let capture = initialFront.hoverController?.view, capture.window === window else {
      throw failure("Hover capture not mounted in the native window")
    }
    guard capture.bounds.width == 120, capture.bounds.height == 70 else {
      throw failure("Hover capture changed the content layout: \(capture.bounds)")
    }
    let local = CGPoint(x: capture.bounds.midX, y: capture.bounds.midY)
    guard
      let event = NSEvent.mouseEvent(
        with: .mouseMoved,
        location: capture.convert(local, to: nil), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0,
        pressure: 0)
    else { throw failure("Cannot create local native event") }
    NSApp.postEvent(event, atStart: false)
    try await settle(2)
    try await press("Allow hover behind", count: 3)
    try await press("Inner action", count: 3)
    guard named("Hover child actions: 1", session.tree.root!) else {
      throw failure("Nested native action did not reach OCaml")
    }
    try await press("Block hover behind", count: 4)
    try await press("Reverse hover regions", count: 6)
    try await press("Reverse hover regions", count: 8)
    let stale = capture.onSample
    try await press("Replace hover handlers", count: 9)
    stale?(
      NativePointer(
        id: 0, localX: 0, localY: 0, globalX: -100, globalY: -100, kind: .mouse, buttons: 0), true)
    try await settle(9)
    try await press("Hide front hover", count: 10)
    try await press("Show front hover", count: 12)
    guard try front() !== initialFront else {
      throw failure("Removed region reused its old identity")
    }
    let current = try front()
    let finalCallback = current.hoverController?.view.onSample
    await session.close()
    guard session.tree.activeHoverWindowCount == 0 else {
      throw failure("Closed session retained its window source")
    }
    finalCallback?(
      NativePointer(id: 0, localX: 0, localY: 0, globalX: 0, globalY: 0, kind: .mouse, buttons: 0),
      true)
    guard session.tree.root == nil else {
      throw failure("Closed session was changed by a native callback")
    }
    print(
      "PASS: actual Gallery Hover ownership, pass-through, reordering, native actions, handler replacement, closure, shared sources and queued movement"
    )
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func failure(_ message: String) -> NSError {
  NSError(domain: "HoverWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
