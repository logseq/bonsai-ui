import AppKit
import SwiftUI

@main struct GestureWindowAcceptance: App {
  @State private var session = BonsaiSession()
  init() { NSApplication.shared.setActivationPolicy(.accessory) }
  var body: some Scene {
    Window("Gesture acceptance", id: "gesture") {
      BonsaiApplicationView(
        entrypoint: ProcessInfo.processInfo.arguments.contains("--single")
          ? "native-gesture-window-single"
          : ProcessInfo.processInfo.arguments.contains("--pointer")
            ? "native-gesture-window-pointer" : "native-gesture-window", session: session
      ).task { await verify(session) }
    }.defaultSize(width: 440, height: 360)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    try await pause(250)
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
      throw failure("Missing test window")
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    try await pause(500)
    if let content = window.contentView { try await settleAccessibility(content) }
    guard NSApp.isActive, window.isKeyWindow else {
      throw failure("Test requires its own active key window")
    }
    guard session.displayedRevision > 0,
      let gesture = session.tree.nodes.values.first(where: { $0.kind == NodeKindId.gesture }),
      window.contentView != nil
    else { throw failure("Actual OCaml Gesture node was not rendered and presented") }
    let frame = try await session.windowHost.layoutRequests.measure(gesture.layoutTarget) {
      session.tree.nodes[gesture.id.node] === gesture && session.displayedRevision > 0
    }
    guard frame.width >= 320, frame.height >= 180 else {
      throw failure("Actual OCaml Gesture node has an invalid measured extent")
    }
    let global = CGPoint(x: frame.minX + 80, y: frame.minY + 40)
    let point = CGPoint(x: global.x, y: window.contentLayoutRect.maxY - global.y)
    let scenario = String((ProcessInfo.processInfo.arguments.last ?? "--recognition").dropFirst(2))
    switch scenario {
    case "pointer":
      func verifyPointer(_ device: Int64?, _ kind: String) async throws {
        let outside = CGPoint(x: frame.minX - 30, y: point.y)
        try await packet(window, type: .mouseMoved, point: outside, device: device)
        try await packet(window, type: .mouseMoved, point: point, device: device)
        try await pause(150)
        try await packet(window, type: .leftMouseDown, point: point, device: device)
        try await packet(window, type: .leftMouseUp, point: point, device: device)
        try await pause(700)
        let records = history(session).dropFirst("Events:".count).split(separator: ";")
        let expectedID = String(device.map { $0 + 1 } ?? 0)
        for name in ["enter-0", "down-0", "up-0"] {
          let record = records.last { $0.hasPrefix(name + ":") }?.split(separator: ":") ?? []
          try expect(
            record.count == 8 && record[1] == expectedID && record[6] == kind,
            "Shared Hover/Gesture identity and kind for \(name), device=\(expectedID), kind=\(kind)",
            session)
        }
        let tap = records.last { $0.hasPrefix("tap-0:") }?.split(separator: ":") ?? []
        try expect(tap.count == 6 && tap[5] == kind, "Tap retained pointer kind \(kind)", session)
      }
      try await verifyPointer(nil, "mouse")
      try await verifyPointer(17, "unknown")
      try await proximity(window, device: 17, kind: 1, entered: true)
      try await verifyPointer(17, "stylus")
      try await proximity(window, device: 17, kind: 3, entered: true)
      try await verifyPointer(17, "inverted-stylus")
      try await proximity(window, device: 29, kind: 1, entered: true)
      try await verifyPointer(29, "stylus")
      try await verifyPointer(17, "inverted-stylus")
      try await proximity(window, device: 17, kind: 3, entered: false)
      try await verifyPointer(17, "unknown")
      try await verifyPointer(29, "stylus")
      try await verifyPointer(nil, "mouse")
    case "single":
      try await click(window, point: point)
      try await pause(700)
      try expect(actions(session) == ["tap-0"], "Tap-only handler did not activate", session)
    case "recognition":
      try await click(window, point: point)
      try await pause(700)
      try expect(actions(session) == ["down-0", "up-0", "tap-0"], "Single-click order", session)
      let records = history(session).dropFirst("Events:".count).split(separator: ";")
      let tap = records.last!.split(separator: ":")
      try expect(
        tap.count == 6 && abs(Double(tap[1])! - 80) < 1
          && abs(Double(tap[2])! - 40) < 1
          && abs(Double(tap[3])! - global.x) < 1
          && abs(Double(tap[4])! - global.y) < 1 && tap[5] == "mouse",
        "Tap local/root coordinates or pointer kind (frame=\(frame), expected=\(global), content=\(window.contentLayoutRect))",
        session)
      let down = records[0].split(separator: ":")
      let up = records[1].split(separator: ":")
      try expect(
        down.count == 8 && up.count == 8 && down[1] == "0" && down[1] == up[1]
          && down[6] == "mouse" && down[7] == "1" && up[7] == "0",
        "Pointer identity, kind or button transitions", session)
      try await click(window, point: point)
      try await pause(80)
      try await click(window, point: point, count: 2)
      try await pause(700)
      try expect(
        actions(session) == [
          "down-0", "up-0", "tap-0", "down-0", "up-0", "down-0", "up-0", "double-0",
        ],
        "Double click must suppress the corresponding single clicks", session)
      try await event(window, .leftMouseDown, at: point)
      try await pause(800)
      try await event(window, .leftMouseUp, at: point)
      try await pause(700)
      try expect(
        Array(actions(session).suffix(3)) == ["down-0", "long-0", "up-0"],
        "Long press must suppress tap", session)
      let before = actions(session)
      let nestedPoint = CGPoint(
        x: frame.midX, y: window.contentLayoutRect.maxY - (frame.minY + 150))
      try await click(window, point: nestedPoint)
      try await pause(700)
      let added = Array(actions(session).dropFirst(before.count))
      try expect(
        added.filter { !$0.hasPrefix("down") && !$0.hasPrefix("up") } == ["nested-0"],
        "Nested Button must own its action", session)
    case "drag":
      try await event(window, .leftMouseDown, at: point)
      try await event(window, .leftMouseDragged, at: CGPoint(x: point.x + 120, y: point.y - 10))
      try await pause(800)
      try await event(window, .leftMouseUp, at: CGPoint(x: point.x + 120, y: point.y - 10))
      try await pause(700)
      try expect(
        actions(session) == ["down-0", "up-0"], "A drag must cancel tap and long press", session)
    case "rebind":
      try await click(window, point: point)
      try press("Replace handler", window: window)
      try await pause(800)
      try expect(
        !actions(session).contains("tap-0"), "Delayed old handler survived replacement", session)
      try await click(window, point: point)
      try await pause(700)
      try expect(
        Array(actions(session).suffix(3)) == ["down-1", "up-1", "tap-1"],
        "Replacement handler did not receive new input", session)
      try await click(window, point: point)
      try press("Remove target", window: window)
      try await pause(800)
      try expect(
        !session.tree.nodes.values.contains { $0.kind == NodeKindId.gesture },
        "Target was not disposed", session)
      try expect(
        actions(session).filter { $0 == "tap-1" }.count == 1,
        "Disposed gesture delivered delayed click", session)
    case "inactive":
      try await click(window, point: point)
      session.isActive = false
      try await pause(800)
      try expect(
        !actions(session).contains("tap-0"), "Inactive session accepted delayed gesture", session)
      session.isActive = true
      try await pause(200)
      try await click(window, point: point)
      try await pause(700)
      try expect(
        actions(session).filter { $0 == "tap-0" }.count == 1,
        "Reactivation did not restore recognition", session)
    default: throw failure("Unknown scenario \(scenario)")
    }
    print("PASS: actual OCaml Gesture window \(scenario): \(history(session))")
    fflush(stdout)
    await session.close()
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    await session.close()
    exit(1)
  }
}

@MainActor private func history(_ session: BonsaiSession) -> String {
  session.tree.nodes.values.compactMap {
    if case .text(let text) = $0.properties, text.value.hasPrefix("Events:") { return text.value }
    return nil
  }.first ?? "MISSING HISTORY"
}
@MainActor private func actions(_ session: BonsaiSession) -> [String] {
  history(session).dropFirst("Events:".count).split(separator: ";").map {
    String($0.split(separator: ":")[0])
  }
}
@MainActor private func expect(_ valid: Bool, _ message: String, _ session: BonsaiSession) throws {
  if !valid { throw failure("\(message): \(history(session))") }
}
@MainActor private func press(_ label: String, window: NSWindow) throws {
  guard
    let button = accessibilityElements(window).first(where: {
      $0.role == "AXButton" && $0.label == label
    }), button.press()
  else {
    throw failure(
      "Missing Button \(label): \(accessibilityElements(window).map { [$0.role, $0.label, $0.value].compactMap { $0 }.joined(separator: ":") })"
    )
  }
}
@MainActor private func event(
  _ window: NSWindow, _ type: NSEvent.EventType, at point: CGPoint, count: Int = 1
) async throws {
  guard
    let value = NSEvent.mouseEvent(
      with: type, location: point, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count,
      pressure: type == .leftMouseUp ? 0 : 1)
  else { throw failure("Cannot create application-local event") }
  NSApp.postEvent(value, atStart: false)
  try await pause(40)
}
@MainActor private func click(_ window: NSWindow, point: CGPoint, count: Int = 1) async throws {
  try await event(window, .leftMouseDown, at: point, count: count)
  try await event(window, .leftMouseUp, at: point, count: count)
}
private func pause(_ milliseconds: Int) async throws {
  try await Task.sleep(for: .milliseconds(milliseconds))
}
private func failure(_ message: String) -> NSError {
  NSError(
    domain: "GestureWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

// Construct native event packets for this process's test window. No event is posted globally.
@MainActor private func packet(
  _ window: NSWindow, type: NSEvent.EventType,
  point: CGPoint, device: Int64?
) async throws {
  let event = NSEvent.mouseEvent(
    with: type, location: point, modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
  if let device {
    let bytes = event.cgEvent!
    bytes.setIntegerValueField(.mouseEventSubtype, value: 1)
    bytes.setIntegerValueField(.tabletEventDeviceID, value: device)
    let native = NSEvent(cgEvent: bytes)!
    guard native.windowNumber == window.windowNumber && native.subtype == .tabletPoint,
      native.deviceID == device
    else { throw failure("Invalid native tablet-point fixture") }
    NSApp.postEvent(native, atStart: false)
  } else {
    NSApp.postEvent(event, atStart: false)
  }
  try await pause(60)
}
@MainActor private func proximity(
  _ window: NSWindow, device: Int64,
  kind: Int64, entered: Bool
) async throws {
  let event = NSEvent.mouseEvent(
    with: .mouseMoved, location: .zero, modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
    context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
  let bytes = event.cgEvent!
  bytes.type = .tabletProximity
  bytes.setIntegerValueField(.tabletProximityEventDeviceID, value: device)
  bytes.setIntegerValueField(.tabletProximityEventPointerType, value: kind)
  bytes.setIntegerValueField(.tabletProximityEventEnterProximity, value: entered ? 1 : 0)
  let native = NSEvent(cgEvent: bytes)!
  guard native.type == .tabletProximity && native.windowNumber == window.windowNumber,
    native.deviceID == device, native.pointingDeviceType.rawValue == kind,
    native.isEnteringProximity == entered
  else { throw failure("Invalid native proximity fixture") }
  NSApp.postEvent(native, atStart: false)
  try await pause(60)
}
