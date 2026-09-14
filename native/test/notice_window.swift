import AppKit
import Observation
import SwiftUI

@MainActor @Observable private final class NoticeWindowModel {
  let session: BonsaiSession
  var events: BonsaiApplicationEvents?
  init() {
    var connect: ((BonsaiApplicationEvents) -> Void)?
    session = BonsaiSession(
      applicationBridge: BonsaiApplicationBridge(request: { $0 }, connected: { connect?($0) }))
    connect = { [weak self] in self?.events = $0 }
  }
}

@main struct NoticeWindowAcceptance: App {
  @State private var model = NoticeWindowModel()
  var body: some Scene {
    Window("Notification Acceptance", id: "notice") {
      BonsaiApplicationView(entrypoint: "native-notice", session: model.session)
        .environment(\.scenePhase, .active)
        .allowsWindowActivationEvents(true)
        .task { await verify(model) }
    }.defaultSize(width: 640, height: 480)
  }
}
private func failure(_ text: String) -> NSError {
  NSError(domain: "NoticeWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
@MainActor private func status(_ model: NoticeWindowModel) -> String {
  model.session.tree.nodes.values.compactMap {
    if case .text(let value) = $0.properties, value.value.hasPrefix("Notices:") {
      return value.value
    }
    return nil
  }.first ?? ""
}
@MainActor private func wait(_ host: NSView, until condition: () -> Bool) async throws {
  for _ in 0..<150 {
    if condition() { return }
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    try await Task.sleep(for: .milliseconds(10))
  }
  throw failure("Native condition did not complete")
}
@MainActor private func verify(_ model: NoticeWindowModel) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing application window") }
    window.makeKeyAndOrderFront(nil)
    try await settleAccessibility(host)
    try await wait(host) { model.events != nil }
    let message = String(repeating: "Swipe this notification ", count: 24)
    try model.events?.send(Data("show:\(message):5000:Unused action".utf8))
    try await wait(host) {
      accessibilityElements(host).contains { $0.label == message || $0.value == message }
    }
    guard
      let element = accessibilityElements(host).first(where: {
        $0.label == message || $0.value == message
      })
    else { throw failure("Notification text was not presented") }
    let selector = NSSelectorFromString("accessibilityFrame")
    guard element.object.responds(to: selector) else {
      throw failure("Notification has no native frame")
    }
    typealias Frame = @convention(c) (AnyObject, Selector) -> CGRect
    let frame = unsafeBitCast(element.object.method(for: selector), to: Frame.self)(
      element.object, selector)
    guard frame.maxY < window.frame.minY + 180 else {
      throw failure("Notification is not in the bottom safe area")
    }
    let point = window.convertPoint(fromScreen: CGPoint(x: frame.midX, y: frame.maxY - 5))
    let start = ProcessInfo.processInfo.systemUptime
    for step in 0...12 {
      let type: NSEvent.EventType =
        step == 0 ? .leftMouseDown : step == 12 ? .leftMouseUp : .leftMouseDragged
      guard
        let event = NSEvent.mouseEvent(
          with: type,
          location: CGPoint(x: point.x, y: point.y - Double(step) * 5), modifierFlags: [],
          timestamp: start + Double(step) * 0.016, windowNumber: window.windowNumber,
          context: nil, eventNumber: step, clickCount: 1, pressure: step == 12 ? 0 : 1)
      else { throw failure("Cannot create local mouse event") }
      NSApp.postEvent(event, atStart: false)
    }
    try await wait(host) { status(model) == "Notices:\(message)=swipe;" }
    guard !status(model).contains("=action;") else {
      throw failure("Swipe activated the action button")
    }
    await model.session.close()
    print(
      "PASS: native notification swipe reaches the actual OCaml result without activating its action"
    )
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error); \(status(model))")
    fflush(stdout)
    exit(1)
  }
}
