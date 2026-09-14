import AppKit
import SwiftUI

@main struct ButtonFocusProbe: App {
  init() { NSApplication.shared.setActivationPolicy(.accessory) }
  var body: some Scene {
    Window("Button Focus Probe", id: "probe") { Probe() }.defaultSize(width: 360, height: 200)
  }
}
struct Probe: View {
  @State private var count = 0
  @State private var text = "Draft"
  @FocusState private var focus: Bool
  var body: some View {
    VStack {
      TextField("Draft", text: $text)
      if ProcessInfo.processInfo.arguments.contains("--all-interactions") {
        Button("Probe") { count += 1 }.focusable(interactions: [.activate, .edit]).focused($focus)
      } else if ProcessInfo.processInfo.arguments.contains("--edit-interaction") {
        Button("Probe") { count += 1 }.focusable(interactions: .edit).focused($focus)
      } else if ProcessInfo.processInfo.arguments.contains("--focusable") {
        Button("Probe") { count += 1 }.focusable(interactions: .activate).focused($focus)
      } else {
        Button("Probe") { count += 1 }.focused($focus)
      }
    }.padding(20).onChange(of: focus) { _, next in print("focus changed to \(next)") }.task {
      try? await Task.sleep(for: .milliseconds(150))
      guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else { exit(2) }
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      focus = true
      try? await Task.sleep(for: .milliseconds(250))
      print(
        "focus=\(focus) keyboardNavigation=\(NSApp.isFullKeyboardAccessEnabled) keyWindow=\(window.isKeyWindow) responder=\(String(describing: window.firstResponder))"
      )
      for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
          with: type, location: .zero, modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false,
          keyCode: 49)!
        window.sendEvent(event)
      }
      try? await Task.sleep(for: .milliseconds(250))
      print("activations=\(count) text=\(text)")
      fflush(stdout)
      exit(0)
    }
  }
}
