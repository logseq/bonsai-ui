import Foundation
import Testing

@testable import BonsaiSwiftUI

@MainActor private final class ShutdownFixture {
  var sender: BonsaiApplicationEvents?
  var ordinary = 0
  var disconnected = 0
  var ready: [Data] = []
  let audit = FileManager.default.temporaryDirectory.appendingPathComponent(
    "shutdown-\(UUID()).log")
  lazy var session = BonsaiSession(
    applicationBridge: BonsaiApplicationBridge(
      request: { [self] bytes in
        ordinary += 1
        return bytes
      },
      connected: { [self] in sender = $0 }, disconnected: { [self] in disconnected += 1 }))
  func start() async throws {
    session.isVisible = true
    session.isActive = true
    try await session.start(entrypoint: "native-shutdown", payload: Data(audit.path.utf8))
    _ = try await session.presented(#require(session.ticket))
  }
  func clean() async {
    await session.close()
    try? FileManager.default.removeItem(at: audit)
  }
}

extension NativeRuntimeTests {

  @Test(arguments: 0...5) @MainActor func shutdownProgressWithoutPresentation(
    mode: Int
  ) async throws {
    let fixture = ShutdownFixture()
    try await fixture.start()
    if mode == 3 {
      try #require(fixture.sender).send(Data([2]))
      _ = try await fixture.session.refresh()
      #expect(fixture.session.ticket != nil)
    }
    if mode == 4 {
      try #require(fixture.sender).send(Data([11]))
      _ = try await fixture.session.refresh()
      try await Task.sleep(for: .milliseconds(40))
    }
    let input = try #require(
      fixture.session.tree.nodes.values.first { $0.bindings[EventTagId.press] != nil })
    if mode == 0 { #expect(fixture.session.activate(input)) }
    if mode != 0 { fixture.session.isVisible = false }
    if mode == 2 { fixture.session.isActive = false }
    let ticket = fixture.session.ticket
    let sender = try #require(fixture.sender)
    if mode == 5 {
      for _ in 0..<1024 { try sender.send(Data([2])) }
      #expect(throws: BonsaiApplicationEvents.SendError.backpressure) { try sender.send(Data()) }
    }
    #if os(macOS)
      let clipboardChanges = NSPasteboard.general.changeCount
    #endif
    let previousAudit = (try? String(contentsOf: fixture.audit, encoding: .utf8)) ?? ""
    let operation = try sender.beginShutdown(
      event: Data([12]), timeout: .seconds(2), accepting: { $0.first == 13 },
      request: { bytes in
        fixture.ready.append(bytes)
        return .finish(Data([99]))
      })
    let duplicate = try sender.beginShutdown(
      event: Data([14]), timeout: .seconds(9), accepting: { _ in false },
      request: { _ in
        Issue.record("Duplicate handler ran")
        return .finish(Data())
      })
    #expect(operation === duplicate)
    #expect(!fixture.session.activate(input))
    #expect(throws: BonsaiApplicationEvents.SendError.closed) { try sender.send(Data()) }
    if let ticket { #expect(try await fixture.session.presented(ticket) == false) }
    #expect(await operation.result == .completed)
    #expect(fixture.ready.count == 1)
    #expect(fixture.ordinary == 0)
    #if os(macOS)
      #expect(NSPasteboard.general.changeCount == clipboardChanges)
    #endif
    #expect(fixture.disconnected == 1)
    #expect(fixture.session.displayedRevision == 0)
    let audit = try String(contentsOf: fixture.audit, encoding: .utf8)
    #expect(!audit.contains("ui-input"))
    #expect(audit.contains("worker-completed\n"))
    #expect(audit.contains("final-reply-accepted\n"))
    #expect(
      audit.components(separatedBy: "after-display").count
        == previousAudit.components(separatedBy: "after-display").count)
    if mode == 5 { #expect(audit.contains("shutdown-event:1025\n")) }
    #expect(audit.components(separatedBy: "worker-closed").count - 1 == 1)
    await fixture.clean()
  }

  @Test(arguments: 0...2) @MainActor func shutdownDeadlineCancellationAndClose(mode: Int)
    async throws
  {
    let fixture = ShutdownFixture()
    try await fixture.start()
    fixture.session.isActive = false
    let sender = try #require(fixture.sender)
    let operation = try sender.beginShutdown(
      event: Data([14]), timeout: .milliseconds(50), accepting: { _ in true },
      request: { _ in .reply(Data()) })
    if mode == 1 { operation.cancel() }
    if mode == 2 { await fixture.session.close() }
    #expect(await operation.result == (mode == 0 ? .timedOut : mode == 1 ? .cancelled : .closed))
    #expect(fixture.disconnected == 1)
    try await fixture.start()
    #expect(throws: BonsaiApplicationEvents.SendError.closed) { try sender.send(Data()) }
    #expect(throws: BonsaiApplicationEvents.SendError.closed) { try operation.send(Data()) }
    #expect(throws: BonsaiApplicationEvents.SendError.closed) {
      try sender.beginShutdown(
        event: Data(), timeout: .seconds(1), accepting: { _ in true },
        request: { _ in .finish(Data()) })
    }
    await fixture.clean()
    #expect(fixture.disconnected == 2)
  }

  @Test @MainActor func shutdownLateHandlerCannotEnterReplacement() async throws {
    let fixture = ShutdownFixture()
    try await fixture.start()
    var finish: CheckedContinuation<BonsaiApplicationShutdown.Response, Never>?
    let operation = try #require(fixture.sender).beginShutdown(
      event: Data([12]), timeout: .seconds(2), accepting: { $0.first == 13 },
      request: { _ in await withCheckedContinuation { finish = $0 } })
    let deadline = ContinuousClock.now + .seconds(1)
    while finish == nil && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(2))
    }
    try #require(finish != nil)
    operation.cancel()
    #expect(await operation.result == .cancelled)
    try await fixture.start()
    finish?.resume(returning: .finish(Data([99])))
    for _ in 0..<5 {
      _ = try await fixture.session.refresh()
      if let ticket = fixture.session.ticket { _ = try await fixture.session.presented(ticket) }
    }
    #expect(fixture.ordinary == 0)
    #expect(fixture.disconnected == 1)
    await fixture.clean()
  }

  @Test @MainActor func shutdownResponseSurvivesSaturatedLifecycleQueue() async throws {
    let fixture = ShutdownFixture()
    try await fixture.start()
    var operation: BonsaiApplicationShutdown!
    operation = try #require(fixture.sender).beginShutdown(
      event: Data([12]), timeout: .seconds(2), accepting: { $0.first == 13 },
      request: { _ in
        for _ in 0..<1024 { try operation.send(Data([2])) }
        #expect(throws: BonsaiApplicationEvents.SendError.backpressure) {
          try operation.send(Data())
        }
        return .finish(Data([99]))
      })
    #expect(await operation.result == .completed)
    #expect(fixture.disconnected == 1)
    await fixture.clean()
  }

  @Test func shutdownNativeTransportRejectsUiWithoutConsumingPresentation() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    do {
      let frame = try await runtime.pump(monotonicNanoseconds: 1)
      let epoch = try WireFrame.decode(frame.bytes).epoch
      let input = try EventBatch.encode(
        epoch: epoch,
        events: [
          NativeEvent(
            sequence: 1, displayedRevision: frame.revision, nodeID: 1, handlerID: 1, payload: .press
          )
        ])
      let rejected = try await runtime.shutdownPump(monotonicNanoseconds: 2, events: input)
      #expect(rejected.status == 1)
      try await runtime.acknowledge(frame, monotonicNanoseconds: 3)
      let drained = try await runtime.shutdownPump(monotonicNanoseconds: 4, events: Data())
      #expect(drained.status == 0)
      #expect(drained.presentationID == 0)
      #expect(drained.revision == frame.revision)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test @MainActor func shutdownInvalidAdmissionDoesNotRetireConnection() async throws {
    let fixture = ShutdownFixture()
    try await fixture.start()
    let sender = try #require(fixture.sender)
    #expect(throws: BonsaiApplicationEvents.SendError.payloadTooLarge) {
      try sender.beginShutdown(
        event: Data(repeating: 0, count: 1_048_577), timeout: .seconds(1),
        accepting: { _ in true }, request: { _ in .finish(Data()) })
    }
    #expect(throws: BonsaiApplicationShutdown.StartError.invalidTimeout) {
      try sender.beginShutdown(
        event: Data(), timeout: .zero, accepting: { _ in true }, request: { _ in .finish(Data()) }
      )
    }
    try sender.send(Data([2]))
    #expect(fixture.disconnected == 0)
    await fixture.clean()
  }
}

#if os(macOS)
  import AppKit
  import SwiftUI
  import Observation
  @MainActor @Observable private final class ShutdownWindowSettings {
    var phase = ScenePhase.active
  }
  @MainActor private struct ShutdownWindowHost: View {
    let settings: ShutdownWindowSettings
    let payload: Data
    let bridge: BonsaiApplicationBridge
    var body: some View {
      BonsaiApplicationView(
        entrypoint: "native-shutdown", payload: payload, applicationBridge: bridge
      )
      .environment(\.scenePhase, settings.phase)
    }
  }
  extension NativeRuntimeTests {
    @Test(arguments: ["visible", "hidden", "inactive", "minimized"])
    @MainActor func shutdownActualNativeWindow(mode: String) async throws {
      initializeAccessibilityApplication()
      let audit = FileManager.default.temporaryDirectory.appendingPathComponent(
        "shutdown-window-\(UUID()).log")
      var sender: BonsaiApplicationEvents?
      var disconnected = 0
      var ordinary = 0
      let bridge = BonsaiApplicationBridge(
        request: { bytes in
          ordinary += 1
          return bytes
        },
        connected: { sender = $0 }, disconnected: { disconnected += 1 })
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 400, height: 220),
        styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
      let settings = ShutdownWindowSettings()
      window.contentView = NSHostingView(
        rootView: ShutdownWindowHost(
          settings: settings, payload: Data(audit.path.utf8), bridge: bridge))
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      defer {
        NSApp.unhide(nil)
        window.deminiaturize(nil)
        window.orderOut(nil)
        window.contentView = nil
        try? FileManager.default.removeItem(at: audit)
      }
      let connectDeadline = ContinuousClock.now + .seconds(3)
      while sender == nil && ContinuousClock.now < connectDeadline {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
      }
      let events = try #require(sender)
      switch mode {
      case "hidden": NSApp.hide(nil)
      case "inactive":
        NSApp.deactivate()
        settings.phase = .inactive
      case "minimized": window.miniaturize(nil)
      default: break
      }
      try await Task.sleep(for: .milliseconds(100))
      if mode == "hidden" { #expect(NSApp.isHidden) }
      if mode == "inactive" { #expect(!NSApp.isActive) }
      if mode == "minimized" { #expect(window.isMiniaturized) }
      let start = ContinuousClock.now
      let operation = try events.beginShutdown(
        event: Data([12]), timeout: .seconds(2),
        accepting: { $0.first == 13 }, request: { _ in .finish(Data([99])) })
      #expect(await operation.result == .completed)
      print(
        "SHUTDOWN_WINDOW mode=\(mode) hidden=\(NSApp.isHidden) active=\(NSApp.isActive) minimized=\(window.isMiniaturized) elapsed=\(start.duration(to: .now))"
      )
      #expect(ordinary == 0)
      #expect(disconnected == 1)
    }
  }
#endif
