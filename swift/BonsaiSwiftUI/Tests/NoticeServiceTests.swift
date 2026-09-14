import AppKit
import Observation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor @Observable private final class NoticeSettings {
  var phase = ScenePhase.active
}
@MainActor private struct NoticeTestHost: View {
  let session: BonsaiSession
  let settings: NoticeSettings
  let entrypoint: String
  var body: some View {
    BonsaiApplicationView(entrypoint: entrypoint, session: session)
      .environment(\.scenePhase, settings.phase)
      .allowsWindowActivationEvents(true)
  }
}
@MainActor private final class NoticeScene {
  let session: BonsaiSession
  let window: NSWindow
  let settings = NoticeSettings()
  var host: NSView?
  private var events: BonsaiApplicationEvents?
  init(width: CGFloat = 640) {
    initializeAccessibilityApplication()
    window = NSWindow(
      contentRect: CGRect(x: 50, y: 50, width: width, height: 480),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    var connect: ((BonsaiApplicationEvents) -> Void)?
    session = BonsaiSession(
      applicationBridge: BonsaiApplicationBridge(request: { $0 }, connected: { connect?($0) }))
    connect = { [weak self] in self?.events = $0 }
  }
  func start(automatic: Bool = false) async throws {
    let hosting = NSHostingView(
      rootView: NoticeTestHost(
        session: session, settings: settings,
        entrypoint: automatic ? "native-notice-auto" : "native-notice"))
    hosting.sizingOptions = []
    host = hosting
    window.contentView = hosting
    window.orderFront(nil)
    if settings.phase == .active {
      try await wait { self.session.tree.root != nil }
    } else {
      try await wait { self.session.isVisible }
    }
    try await settleAccessibility(hosting)
  }
  var status: String {
    session.tree.nodes.values.compactMap {
      if case .text(let value) = $0.properties, value.value.hasPrefix("Notices:") {
        return value.value
      }
      return nil
    }.first ?? ""
  }
  var elements: [AccessibilityElement] { host.map(accessibilityElements) ?? [] }
  func has(_ text: String) -> Bool { elements.contains { $0.label == text || $0.value == text } }
  func button(_ label: String) throws -> AccessibilityElement {
    try #require(elements.first { $0.role == "AXButton" && $0.label == label })
  }
  func tick() async throws {
    host?.layoutSubtreeIfNeeded()
    host?.displayIfNeeded()
    try await Task.sleep(for: .milliseconds(10))
  }
  func wait(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
      if condition() { return }
      try await tick()
    }
    try #require(
      condition(),
      "status=\(status) active=\(session.isActive) displayed=\(session.displayedRevision) notice=\(String(describing: session.windowHost.notices.presentation)) labels=\(elements.compactMap { $0.label ?? $0.value })"
    )
  }
  func sleep(_ milliseconds: Int) async throws {
    for _ in 0..<(milliseconds / 10) { try await tick() }
  }
  func send(_ command: String) throws { try #require(events).send(Data(command.utf8)) }
  func show(_ message: String, duration: Int = 5000, action: String? = nil) throws {
    try send("show:\(message):\(duration):\(action ?? "-")")
  }
  func close() async {
    window.orderOut(nil)
    window.contentView = nil
    host = nil
    await session.close()
  }
  func frame(_ element: AccessibilityElement) throws -> CGRect {
    let selector = NSSelectorFromString("accessibilityFrame")
    try #require(element.object.responds(to: selector))
    typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
    return unsafeBitCast(element.object.method(for: selector), to: Getter.self)(
      element.object, selector)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeNoticeButtonsCompleteRealOcamlAndFitCompactWindows() async throws {
    let scene = NoticeScene(width: 360)
    do {
      try await scene.start()
      try scene.show("Saved notification", action: "Undo")
      try await scene.wait { scene.has("Saved notification") }
      let action = try scene.button("Undo")
      let dismiss = try scene.button("Dismiss notification")
      for button in [action, dismiss] {
        let frame = try scene.frame(button)
        #expect(scene.window.frame.contains(frame))
        #expect(frame.width > 0 && frame.height > 0)
        #expect(
          frame.maxY <= scene.window.frame.minY + 120,
          "Notification must occupy the bottom safe area")
      }
      #expect(action.press())
      try await scene.wait { scene.status.contains("Saved notification=action;") }
      #expect(!scene.has("Saved notification"))
      try scene.show("Dismiss this notification")
      try await scene.wait { scene.has("Dismiss this notification") }
      #expect(try scene.button("Dismiss notification").press())
      try await scene.wait { scene.status.contains("Dismiss this notification=dismiss;") }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func nativeNoticesQueueAndPauseTheirDisplayedTimeout() async throws {
    let scene = NoticeScene()
    do {
      try await scene.start()
      try scene.show("First notification", duration: 300)
      try scene.show("Second notification", action: "Keep")
      try await scene.wait { scene.has("First notification") }
      #expect(!scene.has("Second notification"))
      scene.settings.phase = .background
      try await scene.wait { !scene.session.isActive }
      try await scene.sleep(450)
      #expect(scene.status == "Notices:")
      scene.settings.phase = .active
      try await scene.wait { scene.status.contains("First notification=timeout;") }
      try await scene.wait { scene.has("Second notification") }
      #expect(try scene.button("Keep").press())
      try await scene.wait {
        scene.status == "Notices:First notification=timeout;Second notification=action;"
      }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func nativeNoticesCancelQueuedAndVisibleRequestsAndFenceRetiredButtons()
    async throws
  {
    let scene = NoticeScene()
    do {
      try await scene.start()
      try scene.show("Visible notification", action: "Retired action")
      try scene.show("Queued notification")
      try await scene.wait { scene.has("Visible notification") }
      let retired = try scene.button("Retired action")
      try scene.send("cancel:Queued notification")
      try await scene.wait { scene.status.contains("Queued notification=cancelled;") }
      #expect(scene.has("Visible notification"))
      try scene.send("cancel:Visible notification")
      try await scene.wait { scene.status.contains("Visible notification=cancelled;") }
      try scene.show("Next notification", action: "Next action")
      try await scene.wait { scene.has("Next notification") }
      _ = retired.press()
      try await scene.sleep(80)
      #expect(scene.has("Next notification"))
      #expect(!scene.status.contains("Next notification="))
      await scene.close()
      try await scene.start()
      try scene.show("Restarted notification", action: "Restarted action")
      try await scene.wait { scene.has("Restarted notification") }
      _ = retired.press()
      #expect(try scene.button("Restarted action").press())
      try await scene.wait { scene.status == "Notices:Restarted notification=action;" }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func nativeStartupNoticeWaitsForActivePresentation() async throws {
    let scene = NoticeScene()
    scene.settings.phase = .background
    do {
      try await scene.start(automatic: true)
      #expect(scene.session.displayedRevision == 0)
      #expect(!scene.has("Startup notice"))
      try await scene.sleep(200)
      #expect(scene.status.isEmpty)
      scene.settings.phase = .active
      try await scene.wait { scene.has("Startup notice") }
      #expect(try scene.button("Continue").press())
      try await scene.wait { scene.status == "Notices:Startup notice=action;" }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

}

struct NoticeWireTests {
  private func bytes(message: String = "Message", action: String? = "Undo", duration: UInt32 = 4000)
    throws -> Data
  {
    var writer = WireWriter()
    writer.integer(UInt64(1))
    writer.integer(UInt16(15))
    try writer.string(message)
    writer.integer(UInt8(action == nil ? 0 : 1))
    if let action { try writer.string(action) }
    writer.integer(duration)
    return writer.bytes
  }
  @Test func notificationCommandsRequireContentAndPositiveDuration() throws {
    for data in [
      try bytes(), try bytes(message: "保存しました😀", action: nil), try bytes(duration: .max),
    ] {
      var reader = WireReader(data)
      _ = try HostCommand.decode(&reader)
      #expect(reader.remaining == 0)
    }
    let valid = try bytes()
    for count in 0..<valid.count {
      #expect(throws: (any Error).self) {
        var reader = WireReader(valid.prefix(count))
        _ = try HostCommand.decode(&reader)
      }
    }
    for data in [try bytes(message: " \n\t"), try bytes(action: ""), try bytes(duration: 0)] {
      #expect(throws: (any Error).self) {
        var reader = WireReader(data)
        _ = try HostCommand.decode(&reader)
      }
    }
  }
}
