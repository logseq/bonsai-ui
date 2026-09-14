import AppKit
import Testing

@testable import BonsaiSwiftUI

@MainActor private func connectHoverCapture(
  _ capture: AppKitHoverCapture, emit: @escaping (NativeEventPayload) -> Void
) {
  let router = HoverRouter()
  router.replace([
    HoverRouter.Region(
      id: RenderIdentity(epoch: 1, node: 1), subtree: 0..<1,
      order: 0, blocksBehind: true, bindings: [5: 1, 6: 2],
      locate: { [weak capture] sample in capture?.locate(sample) },
      emit: {
        emit($0)
        return true
      })
  ])
  router.setPresented(true)
  capture.onSample = { [weak capture] pointer, present in
    guard let window = capture?.window else { return }
    router.receive(
      HoverRouter.Sample(
        pointer: HoverSample(
          id: pointer.id, kind: pointer.kind,
          position: CGPoint(x: pointer.globalX, y: pointer.globalY), buttons: pointer.buttons),
        window: ObjectIdentifier(window), present: present))
  }
  capture.onGeometry = { router.refresh() }
}

@MainActor private func hoverEvent(
  _ type: NSEvent.EventType, window: NSWindow, point: CGPoint, number: Int = 1
) throws -> NSEvent {
  try #require(
    NSEvent.enterExitEvent(
      with: type, location: point, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: number, trackingNumber: 0,
      userData: nil))
}

@MainActor struct AppKitHoverCaptureTests {
  @Test func nativeCoordinatesAndTrackingLifecycle() throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: CGRect(x: 10, y: 20, width: 300, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let root = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    window.contentView = root
    let capture = AppKitHoverCapture(frame: CGRect(x: 40, y: 50, width: 100, height: 80))
    var events: [NativeEventPayload] = []
    connectHoverCapture(capture) { events.append($0) }
    root.addSubview(capture)
    window.orderFront(nil)
    capture.setCaptureEnabled(true)
    capture.updateTrackingAreas()
    let area = try #require(capture.trackingAreas.first)
    #expect(area.options.contains(.enabledDuringMouseDrag))
    #expect(area.options.contains(.inVisibleRect))
    #expect(area.options.contains(.activeInActiveApp))
    capture.updateTrackingAreas()
    #expect(capture.trackingAreas.first === area)
    #expect(capture.hitTest(CGPoint(x: 50, y: 60)) == nil)
    let enter = try hoverEvent(.mouseEntered, window: window, point: CGPoint(x: 60, y: 100))
    capture.mouseEntered(with: enter)
    capture.mouseEntered(with: enter)
    #expect(events.count == 1)
    if case .pointerEnter(let pointer) = try #require(events.first) {
      #expect(pointer.id == 0 && pointer.kind == .mouse)
      #expect(pointer.localX == 20 && pointer.localY == 30)
      #expect(pointer.globalX == 60 && pointer.globalY == 100)
      #expect(pointer.buttons == UInt32(NSEvent.pressedMouseButtons))
    } else {
      Issue.record("Missing native enter")
    }
    let leave = try hoverEvent(.mouseExited, window: window, point: CGPoint(x: 30, y: 150))
    capture.mouseExited(with: leave)
    capture.mouseExited(with: leave)
    #expect(events.count == 2)
    if case .pointerLeave(let pointer) = try #require(events.last) {
      #expect(pointer.localX == -10 && pointer.localY == -20)
      #expect(pointer.globalX == 30 && pointer.globalY == 50)
    } else {
      Issue.record("Missing native leave")
    }

    capture.setCaptureEnabled(false)
    capture.mouseEntered(with: enter)
    #expect(events.count == 2 && capture.trackingAreas.isEmpty)
    capture.setCaptureEnabled(true)
    capture.mouseEntered(with: enter)
    #expect(events.count == 3)
    root.isHidden = true
    capture.mouseExited(with: leave)
    #expect(events.count == 3)
    root.isHidden = false
    capture.mouseEntered(with: enter)
    #expect(events.count == 4)
    capture.removeFromSuperview()
    capture.mouseExited(with: leave)
    #expect(events.count == 4 && capture.trackingAreas.isEmpty)
    root.addSubview(capture)
    capture.mouseEntered(with: enter)
    #expect(events.count == 5)
    capture.dispose()
    capture.mouseExited(with: leave)
    capture.setCaptureEnabled(true)
    #expect(events.count == 5 && capture.trackingAreas.isEmpty)
    #expect(capture.onSample == nil)
  }

  @Test func normalizedCoordinatesRespectFlippedAndScaledAncestorsAndRejectForeignWindows() throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    let foreign = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    foreign.isReleasedWhenClosed = false
    defer {
      window.close()
      foreign.close()
    }
    final class FlippedView: NSView { override var isFlipped: Bool { true } }
    let root = FlippedView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    window.contentView = root
    let capture = AppKitHoverCapture(frame: CGRect(x: 40, y: 50, width: 100, height: 80))
    capture.bounds = CGRect(x: 10, y: 20, width: 50, height: 40)
    var events: [NativeEventPayload] = []
    connectHoverCapture(capture) { events.append($0) }
    root.addSubview(capture)
    window.orderFront(nil)
    capture.setCaptureEnabled(true)
    capture.mouseEntered(
      with: try hoverEvent(
        .mouseEntered, window: foreign, point: CGPoint(x: 60, y: 100)))
    #expect(events.isEmpty)
    capture.mouseEntered(
      with: try hoverEvent(
        .mouseEntered, window: window, point: CGPoint(x: 60, y: 100), number: 999))
    if case .pointerEnter(let pointer) = try #require(events.first) {
      #expect(pointer.id == 0)
      #expect(pointer.localX == 10 && pointer.localY == 25)
      #expect(pointer.globalX == 60 && pointer.globalY == 100)
    } else {
      Issue.record("Missing transformed enter")
    }
    window.orderOut(nil)
    capture.mouseExited(
      with: try hoverEvent(
        .mouseExited, window: window, point: CGPoint(x: 0, y: 0)))
    #expect(events.count == 1)
    window.orderFront(nil)
    capture.mouseEntered(
      with: try hoverEvent(
        .mouseEntered, window: window, point: CGPoint(x: 60, y: 100)))
    #expect(events.count == 2)
  }
}

extension NativeRuntimeTests {
  @MainActor @Test func appKitCapturedHoverReachesOcaml() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-pointer-events")
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let capture = AppKitHoverCapture(frame: CGRect(x: 40, y: 50, width: 100, height: 80))
    defer {
      capture.dispose()
      window.close()
    }
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      var bindings: [Int: UInt64] = [:]
      var node: UInt64 = 0
      for operation in frame.operations where operation.opcode == OperationId.createNode {
        var reader = WireReader(operation.body)
        let id = try reader.integer(UInt64.self)
        guard try reader.integer(UInt16.self) == NodeKindId.hoverRegion else { continue }
        node = id
        _ = try reader.integer(UInt8.self)
        let count = try reader.integer(UInt16.self)
        for _ in 0..<count {
          let tag = Int(try reader.integer(UInt16.self))
          bindings[tag] = try reader.integer(UInt64.self)
        }
      }
      #expect(bindings.count == 2)
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      let root = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
      window.contentView = root
      root.addSubview(capture)
      var payloads: [NativeEventPayload] = []
      connectHoverCapture(capture) { payloads.append($0) }
      window.orderFront(nil)
      capture.setCaptureEnabled(true)
      capture.mouseEntered(
        with: try hoverEvent(
          .mouseEntered, window: window, point: CGPoint(x: 60, y: 100)))
      capture.mouseExited(
        with: try hoverEvent(
          .mouseExited, window: window, point: CGPoint(x: 30, y: 150)))
      #expect(payloads.count == 2)
      let events = try payloads.enumerated().map { index, payload in
        NativeEvent(
          sequence: UInt64(index + 1), displayedRevision: frame.revision, nodeID: node,
          handlerID: try #require(bindings[payload.tag]), payload: payload)
      }
      let updated = try await runtime.pump(
        monotonicNanoseconds: 3, events: EventBatch.encode(epoch: frame.epoch, events: events))
      let buttons = NSEvent.pressedMouseButtons
      let expected =
        "enter:0:20.000:30.000:60.000:100.000:mouse:\(buttons);"
        + "leave:0:-10.000:-20.000:30.000:50.000:mouse:\(buttons);"
      #expect(updated.bytes.range(of: Data(expected.utf8)) != nil)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
