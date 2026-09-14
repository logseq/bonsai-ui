import AppKit
import SwiftUI

@main struct RemovalWindowAcceptance: App {
  @State private var session = BonsaiSession()
  private let vertical = CommandLine.arguments.contains("--vertical")
  private let rtl = CommandLine.arguments.contains("--rtl")
  var body: some Scene {
    Window("Removal Acceptance", id: "removal") {
      BonsaiApplicationView(
        entrypoint: vertical ? "native-removal-v" : "native-removal-h", session: session
      )
      .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
      .allowsWindowActivationEvents(true)
      .frame(minWidth: 700, minHeight: 600)
      .task { await verify(session) }
    }.defaultSize(width: 700, height: 600)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    let window = try require(NSApp.windows.first { $0.contentView != nil })
    let host = try require(window.contentView)
    window.makeKeyAndOrderFront(nil)
    func contains(_ text: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let value) = $0.properties { return value.value == text }
        return false
      }
    }
    func waitFor(_ text: String) async throws {
      for _ in 0..<80 {
        try await settleAccessibility(host)
        if contains(text) { return }
      }
      let diagnostics = session.tree.nodes.values.compactMap { node -> String? in
        guard let c = node.removalController else { return nil }
        return
          "\(c.properties.title): ready=\(c.canRequest), busy=\(c.busy), offset=\(c.offset), length=\(c.length), state=\(c.properties.state)"
      }
      throw failure("Missing \(text); key=\(window.isKeyWindow); \(diagnostics)")
    }
    try await waitFor("Item 1")
    let row = try require(
      accessibilityElements(host).first { $0.actions.contains { $0.name == "Delete 1" } })
    let selector = NSSelectorFromString("accessibilityFrame")
    typealias FrameGetter = @convention(c) (AnyObject, Selector) -> CGRect
    let getter = unsafeBitCast(row.object.method(for: selector), to: FrameGetter.self)
    let frame = getter(row.object, selector)
    guard frame.width >= 450 && frame.height >= 100 else {
      throw failure("Invalid removal frame: \(frame)")
    }
    let vertical = CommandLine.arguments.contains("--vertical")
    let rtl = CommandLine.arguments.contains("--rtl")
    let reverse = CommandLine.arguments.contains("--reverse")
    let middle = CGPoint(x: frame.midX, y: frame.midY)
    let cross = CGPoint(x: middle.x + (vertical ? 60 : 0), y: middle.y + (vertical ? 0 : 45))
    try await drag(window, from: middle, to: cross)
    guard contains("Requests: 0") else { throw failure("Cross-axis gesture requested removal") }
    var from =
      vertical
      ? CGPoint(x: frame.midX, y: frame.maxY - 5) : CGPoint(x: frame.minX + 24, y: frame.midY)
    var to =
      vertical
      ? CGPoint(x: frame.midX, y: frame.minY + 5) : CGPoint(x: frame.maxX - 24, y: frame.midY)
    if reverse { swap(&from, &to) }
    // Do not start a content gesture in the window resize border.
    let interior = window.frame.insetBy(dx: 12, dy: 12)
    guard interior.contains(from), interior.contains(to) else {
      throw failure("Drag enters native window chrome: row=\(frame), window=\(window.frame)")
    }
    try await drag(window, from: from, to: to)
    try await waitFor("Requests: 1")
    let direction = vertical ? (reverse ? 2 : 3) : (reverse == rtl ? 0 : 1)
    guard contains("Direction: \(direction)"), contains("Pending: 1"), contains("Item 1") else {
      throw failure("Wrong request direction or premature removal")
    }
    try await drag(window, from: from, to: to)
    guard contains("Requests: 1") else {
      throw failure("Pending item accepted a duplicate request")
    }
    let accept = try require(
      accessibilityElements(host).first { $0.role == "AXButton" && $0.label == "Accept request" })
    guard accept.press() else { throw failure("Accept command failed") }
    try await waitFor("Removed: 1")
    guard !contains("Item 1"), contains("Item 2") else { throw failure("Wrong item removed") }
    await session.close()
    print("PASS: native removal direction, pending confirmation and completion")
    fflush(stdout)
    exit(0)
  } catch {
    await session.close()
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}

@MainActor private func drag(_ window: NSWindow, from: CGPoint, to: CGPoint) async throws {
  let time = ProcessInfo.processInfo.systemUptime
  for step in 0...12 {
    let fraction = Double(step) / 12
    let point = window.convertPoint(
      fromScreen: CGPoint(
        x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction))
    let type: NSEvent.EventType =
      step == 0 ? .leftMouseDown : step == 12 ? .leftMouseUp : .leftMouseDragged
    let event = try require(
      NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [],
        timestamp: time + Double(step) * 0.016, windowNumber: window.windowNumber, context: nil,
        eventNumber: step, clickCount: 1, pressure: step == 12 ? 0 : 1))
    NSApp.postEvent(event, atStart: false)
  }
  try await settleAccessibility(try require(window.contentView))
}
private func failure(_ text: String) -> NSError {
  NSError(domain: "RemovalWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
private func require<T>(_ value: T?) throws -> T {
  guard let value else { throw failure("Missing native object") }
  return value
}
