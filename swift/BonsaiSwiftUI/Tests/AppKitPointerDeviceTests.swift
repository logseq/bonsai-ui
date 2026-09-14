import AppKit
import Testing

@testable import BonsaiSwiftUI

@MainActor struct AppKitPointerDeviceTests {
  @Test func actualNativePacketsPreserveDeviceIdentityAndProximityKindsAcrossWindows() throws {
    initializeAccessibilityApplication()
    let first = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 200, height: 160),
      styleMask: .borderless, backing: .buffered, defer: false)
    let second = NSWindow(
      contentRect: CGRect(x: 220, y: 0, width: 200, height: 160),
      styleMask: .borderless, backing: .buffered, defer: false)
    first.isReleasedWhenClosed = false
    second.isReleasedWhenClosed = false
    first.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 160))
    second.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 160))
    first.orderFront(nil)
    second.orderFront(nil)
    defer {
      first.close()
      second.close()
    }
    let devices = AppKitPointerDevices()
    var observed: [HoverSample] = []
    let source = AppKitHoverSource(window: first, devices: devices) { observed.append($0.sample) }
    defer { source.dispose() }

    func move(_ device: Int64?, kind: NativePointer.Kind) throws {
      let before = observed.count
      NSApp.sendEvent(try packet(first, device: device))
      #expect(observed.count == before + 1)
      let value = try #require(observed.last)
      #expect(value.id == UInt64(device.map { $0 + 1 } ?? 0))
      #expect(value.kind == kind)
    }
    try move(nil, kind: .mouse)
    try move(17, kind: .unknown)
    NSApp.sendEvent(try packet(second, device: 17, proximity: (1, true)))
    try move(17, kind: .stylus)
    NSApp.sendEvent(try packet(first, device: 17, proximity: (3, true)))
    try move(17, kind: .invertedStylus)
    NSApp.sendEvent(try packet(first, device: 29, proximity: (1, true)))
    try move(29, kind: .stylus)
    try move(17, kind: .invertedStylus)
    NSApp.sendEvent(try packet(first, device: 17, proximity: (3, false)))
    try move(17, kind: .unknown)
    try move(29, kind: .stylus)
    try move(nil, kind: .mouse)
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    try move(29, kind: .unknown)
    NSApp.sendEvent(try packet(first, device: 29, proximity: (1, true)))
    try move(29, kind: .stylus)

    var sibling: HoverSample?
    let other = AppKitHoverSource(window: second, devices: devices) { sibling = $0.sample }
    source.dispose()
    NSApp.sendEvent(try packet(second, device: 29))
    #expect(sibling?.kind == .stylus && sibling?.id == 30)
    other.dispose()
    let before = observed.count
    NSApp.sendEvent(try packet(first, device: 29))
    #expect(observed.count == before)
    let replacement = AppKitHoverSource(window: first, devices: devices) {
      observed.append($0.sample)
    }
    defer { replacement.dispose() }
    try move(29, kind: .unknown)
  }

  // Native AppKit packet fixtures are delivered only to this test process.
  private func packet(_ window: NSWindow, device: Int64?, proximity: (Int64, Bool)? = nil) throws
    -> NSEvent
  {
    let mouse = try #require(
      NSEvent.mouseEvent(
        with: .mouseMoved,
        location: CGPoint(x: 60, y: 70), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
    guard let device else { return mouse }
    let bytes = try #require(mouse.cgEvent)
    if let (kind, entered) = proximity {
      bytes.type = .tabletProximity
      bytes.setIntegerValueField(.tabletProximityEventDeviceID, value: device)
      bytes.setIntegerValueField(.tabletProximityEventPointerType, value: kind)
      bytes.setIntegerValueField(.tabletProximityEventEnterProximity, value: entered ? 1 : 0)
    } else {
      bytes.setIntegerValueField(.mouseEventSubtype, value: 1)
      bytes.setIntegerValueField(.tabletEventDeviceID, value: device)
    }
    let event = try #require(NSEvent(cgEvent: bytes))
    #expect(event.windowNumber == window.windowNumber)
    #expect(event.deviceID == device)
    if let (kind, entered) = proximity {
      #expect(event.type == .tabletProximity)
      #expect(event.pointingDeviceType.rawValue == kind)
      #expect(event.isEnteringProximity == entered)
    } else {
      #expect(event.type == .mouseMoved && event.subtype == .tabletPoint)
    }
    return event
  }
}
