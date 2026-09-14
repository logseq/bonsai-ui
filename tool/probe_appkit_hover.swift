import AppKit
import SwiftUI

@MainActor final class HoverProbe: NSView {
  static weak var current: HoverProbe?
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    Self.current = self
  }
  required init?(coder: NSCoder) { fatalError() }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [
          .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect,
          .enabledDuringMouseDrag,
        ], owner: self))
  }
  override func mouseEntered(with event: NSEvent) {
    print("ENTER", convert(event.locationInWindow, from: nil))
    fflush(stdout)
  }
  override func mouseExited(with event: NSEvent) {
    print("EXIT", convert(event.locationInWindow, from: nil))
    fflush(stdout)
  }
  override func mouseMoved(with event: NSEvent) {
    print("MOVE", convert(event.locationInWindow, from: nil))
    fflush(stdout)
  }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
struct Probe: NSViewRepresentable {
  func makeNSView(context: Context) -> HoverProbe { HoverProbe() }
  func updateNSView(_ view: HoverProbe, context: Context) {}
}
@main struct HoverDispatchProbe: App {
  init() { NSApplication.shared.setActivationPolicy(.accessory) }
  var body: some Scene {
    Window("Hover Dispatch Probe", id: "hover-probe") {
      Text("Hover target").frame(width: 160, height: 80).background(.blue)
        .background(Probe()).padding(30)
        .task {
          try? await Task.sleep(for: .milliseconds(300))
          guard let view = HoverProbe.current, let window = view.window else { exit(2) }
          window.makeKeyAndOrderFront(nil)
          window.acceptsMouseMovedEvents = true
          view.updateTrackingAreas()
          print("PROBE", window.isKeyWindow, view.frame, view.trackingAreas.count)
          for location in [
            CGPoint(x: -10, y: -10), CGPoint(x: 30, y: 30), CGPoint(x: 60, y: 30),
            CGPoint(x: 200, y: 100),
          ] {
            let event = NSEvent.mouseEvent(
              with: .mouseMoved, location: view.convert(location, to: nil), modifierFlags: [],
              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
              context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
            NSApplication.shared.sendEvent(event)
            try? await Task.sleep(for: .milliseconds(100))
          }
          fflush(stdout)
          exit(0)
        }
    }.defaultSize(width: 300, height: 200)
  }
}
