import AppKit
import SwiftUI

@MainActor final class ClickProbe: NSClickGestureRecognizer {
  static var recognitions = 0
  override func mouseDown(with event: NSEvent) {
    print("recognizer down \(event.locationInWindow)")
    super.mouseDown(with: event)
  }
  override func mouseUp(with event: NSEvent) {
    print("recognizer up \(event.locationInWindow)")
    super.mouseUp(with: event)
  }
}
struct ProbeClick: NSGestureRecognizerRepresentable {
  func makeNSGestureRecognizer(context: Context) -> ClickProbe {
    let recognizer = ClickProbe()
    recognizer.name = "Probe click"
    print("created recognizer")
    return recognizer
  }
  func handleNSGestureRecognizerAction(_ recognizer: ClickProbe, context: Context) {
    ClickProbe.recognitions += 1
    print(
      "recognized \(recognizer.state.rawValue) local=\(context.converter.localLocation) global=\(context.converter.location(in: .global))"
    )
    fflush(stdout)
  }
}
@main struct NativeGestureProbe: App {
  init() { NSApplication.shared.setActivationPolicy(.accessory) }
  var body: some Scene {
    Window("Native Gesture Probe", id: "probe") {
      VStack {
        Text("Gesture target").frame(width: 280, height: 120).background(.blue.opacity(0.2))
          .gesture(ProbeClick())
        Button("Nested button") { print("button action") }
      }.frame(width: 320, height: 220).task {
        if ProcessInfo.processInfo.arguments.contains("--interactive") { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else { exit(2) }
        if ProcessInfo.processInfo.arguments.contains("--activate") {
          NSApp.activate(ignoringOtherApps: true)
          window.makeKeyAndOrderFront(nil)
          try? await Task.sleep(for: .milliseconds(100))
        }
        print("window visible=\(window.isVisible) frame=\(window.frame)")
        let point = NSPoint(x: 160, y: 140)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
          let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
          NSApp.postEvent(event, atStart: false)
          try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(800))
        print(
          "recognitions=\(ClickProbe.recognitions) active=\(NSApp.isActive) keyWindow=\(window.isKeyWindow)"
        )
        fflush(stdout)
        exit(ClickProbe.recognitions == 1 ? 0 : 1)
      }
    }.defaultSize(width: 320, height: 220)
  }
}
