import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor private final class ScrollServiceScene {
  let session: BonsaiSession
  let window: NSWindow
  let windowHost = NativeWindowHost()
  private let owner = NSView()
  private var events: BonsaiApplicationEvents?
  private var hosting: NSView?
  private var initialOrigin = CGPoint.zero
  let horizontal: Bool
  let rtl: Bool
  init(horizontal: Bool = false, rtl: Bool = false) {
    self.horizontal = horizontal
    self.rtl = rtl
    initializeAccessibilityApplication()
    window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 660, height: 540),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    var connect: ((BonsaiApplicationEvents) -> Void)?
    session = BonsaiSession(
      windowHost: windowHost,
      applicationBridge: BonsaiApplicationBridge(
        request: { $0 }, connected: { connect?($0) }))
    connect = { [weak self] in self?.events = $0 }
    session.isVisible = true
  }
  func start(kind: Int = 0) async throws {
    try await session.start(entrypoint: "native-scroll-service-\(kind)-\(horizontal ? "h" : "v")")
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(session.tree.root)) {
        _ = self.session.activate($0)
      }.environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
    host.sizingOptions = []
    hosting = host
    window.contentView = host
    window.orderFront(nil)
    windowHost.attach(window: window, title: "Scroll Service", owner: owner)
    try await settle()
    initialOrigin = try native().contentView.bounds.origin
  }
  var status: String {
    session.tree.nodes.values.compactMap {
      if case .text(let value) = $0.properties, value.value.hasPrefix("Scroll service:") {
        return value.value
      }
      return nil
    }.first ?? ""
  }
  func target() throws -> RenderNodeState {
    try #require(session.tree.nodes.values.first { $0.properties.scrollAxis != nil })
  }
  func native() throws -> NSScrollView {
    var pending = [try #require(hosting)]
    while let view = pending.popLast() {
      if let scroll = view as? NSScrollView { return scroll }
      pending.append(contentsOf: view.subviews)
    }
    throw NSError(domain: "ScrollServiceTests", code: 1)
  }
  func extent() throws -> Double {
    let scroll = try native()
    let document = try #require(scroll.documentView)
    return max(
      0,
      horizontal
        ? document.frame.width - scroll.contentView.bounds.width
        : document.frame.height - scroll.contentView.bounds.height)
  }
  func offset() throws -> Double {
    let scroll = try native()
    return horizontal
      ? (rtl
        ? initialOrigin.x - scroll.contentView.bounds.minX
        : scroll.contentView.bounds.minX - initialOrigin.x)
      : scroll.contentView.bounds.minY - initialOrigin.y
  }
  func tick(present: Bool = true) async throws {
    _ = try await session.refresh()
    hosting?.layoutSubtreeIfNeeded()
    hosting?.displayIfNeeded()
    if present, let ticket = session.ticket { _ = try await session.presented(ticket) }
    try await Task.sleep(for: .milliseconds(10))
  }
  func settle() async throws { for _ in 0..<20 { try await tick() } }
  func send(_ command: String) throws { try #require(events).send(Data(command.utf8)) }
  func request(
    _ alignment: Double, animated: Bool = false, node: UInt64? = nil,
    prefix: String = "scroll"
  ) throws {
    try send("\(prefix):\(node ?? target().id.node):\(alignment):\(animated)")
  }
  func result(after before: String) async throws -> String {
    for _ in 0..<150 {
      if status != before { return String(status.dropFirst(before.count)) }
      try await tick()
    }
    Issue.record("OCaml scroll response was not delivered")
    return "missing"
  }
  func close() async {
    await session.close()
    window.orderOut(nil)
    window.contentView = nil
    hosting = nil
  }
}

extension NativeRuntimeTests {
  @Test(arguments: [0, 1, 2, 3], [(false, false), (false, true), (true, false), (true, true)])
  @MainActor func hostScrollRequestsMoveActualOCamlContainers(kind: Int, layout: (Bool, Bool))
    async throws
  {
    let scene = ScrollServiceScene(horizontal: layout.0, rtl: layout.1)
    do {
      try await scene.start(kind: kind)
      let node = try scene.target()
      let native = try scene.native()
      for (alignment, animated) in [(0.5, false), (1.5, true), (-0.5, false)] {
        let before = scene.status
        let started = ContinuousClock.now
        try scene.request(alignment, animated: animated)
        #expect(try await scene.result(after: before) == "ok;")
        if animated { #expect(started.duration(to: .now) >= .milliseconds(200)) }
        try await scene.settle()
        let expected = try scene.extent() * min(1, max(0, alignment))
        let observed = try scene.offset()
        #expect(
          abs(observed - expected) < 2,
          "kind \(kind) layout \(layout) alignment \(alignment) offset \(observed) expected \(expected) bounds \(native.contentView.bounds) document \(native.documentView!.frame)"
        )
        #expect(try scene.target() === node)
        #expect(try scene.native() === native)
      }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func hostScrollDefersPresentationCancelsAndRejectsRetiredTargets() async throws {
    let scene = ScrollServiceScene()
    do {
      try await scene.start()
      let id = try scene.target().id.node
      let before = scene.status
      try scene.request(1)
      try await scene.tick(present: false)
      #expect(scene.session.ticket != nil)
      #expect(try scene.offset() < 1)
      #expect(scene.status == before)
      scene.session.isActive = false
      if let ticket = scene.session.ticket { _ = try await scene.session.presented(ticket) }
      try await scene.settle()
      #expect(scene.status == before)
      #expect(try scene.offset() < 1)
      scene.session.isActive = true
      #expect(try await scene.result(after: before) == "ok;")
      try await scene.settle()
      let end = try scene.offset()
      let cancelled = scene.status
      try scene.request(0, prefix: "cancelled")
      #expect(try await scene.result(after: cancelled) == "cancelled;")
      #expect(abs(try scene.offset() - end) < 1)
      let running = scene.status
      try scene.request(0, animated: true)
      try await scene.tick()
      try scene.send("cancel")
      #expect(try await scene.result(after: running) == "cancelled;")
      try await scene.settle()
      let stopped = try scene.offset()
      try await scene.settle()
      #expect(abs(try scene.offset() - stopped) < 1)
      try scene.send("remove")
      try await scene.settle()
      let removed = scene.status
      try scene.request(1, node: id)
      #expect(try await scene.result(after: removed) == "error;")
      let nonScroll = try #require(
        scene.session.tree.nodes.values.first {
          if case .text = $0.properties { return true }
          return false
        })
      let wrong = scene.status
      try scene.request(1, node: nonScroll.id.node)
      #expect(try await scene.result(after: wrong) == "error;")
      try scene.send("restore")
      try await scene.settle()
      #expect(try scene.target().id.node != id)
      let restored = scene.status
      try scene.request(1)
      #expect(try await scene.result(after: restored) == "ok;")
      await scene.close()
      #expect(scene.session.tree.root == nil)
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func hostScrollShortContentCompletesWithoutTravel() async throws {
    let scene = ScrollServiceScene()
    do {
      try await scene.start(kind: 4)
      for animated in [false, true] {
        let before = scene.status
        try scene.request(1, animated: animated)
        #expect(try await scene.result(after: before) == "ok;")
        #expect(try scene.offset() == 0)
      }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }
}

struct ScrollServiceWireTests {
  private func body(_ alignment: Double, flag: UInt8 = 1, target: UInt64 = 7) -> Data {
    var writer = WireWriter()
    writer.integer(UInt64(1))
    writer.integer(UInt16(8))
    writer.integer(target)
    writer.integer(alignment.bitPattern)
    writer.integer(flag)
    return writer.bytes
  }
  @Test func normalizedScrollCommandsRequireFiniteCompletePayloads() throws {
    for value in [-2.0, 0, 0.5, 1, 3] {
      var reader = WireReader(body(value))
      _ = try HostCommand.decode(&reader)
      #expect(reader.remaining == 0)
    }
    let valid = body(0.5)
    for count in 0..<valid.count {
      #expect(throws: (any Error).self) {
        var reader = WireReader(valid.prefix(count))
        _ = try HostCommand.decode(&reader)
      }
    }
    for data in [
      body(.nan), body(.infinity), body(-.infinity), body(0, flag: 2), body(0, target: 0),
    ] {
      #expect(throws: (any Error).self) {
        var reader = WireReader(data)
        _ = try HostCommand.decode(&reader)
      }
    }
  }
}
