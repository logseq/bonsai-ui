import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test(arguments: [0, 1, 2, 3], [(false, false), (false, true), (true, false), (true, true)])
  @MainActor
  func actualScrollObserversPreserveTravelAndNativeIdentity(
    kind: Int, layout: (horizontal: Bool, rtl: Bool)
  )
    async throws
  {
    let (horizontal, rtl) = layout
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(
        entrypoint: "native-scroll-observer-\(kind)-\(horizontal ? "h" : "v")")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { _ = session.activate($0) }
        )
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
      host.sizingOptions = []
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 640, height: 540),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func settle() async throws {
        for _ in 0..<3 {
          _ = try await session.refresh()
          if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
          try await settleAccessibility(host)
        }
      }
      func modelText() -> [String] {
        session.tree.nodes.values.compactMap {
          if case .text(let text) = $0.properties, text.value.hasPrefix("Observed:") {
            return text.value
          }
          return nil
        }
      }
      func hasText(_ value: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == value }
          return false
        }
      }
      func button(_ label: String) throws -> AccessibilityElement {
        try #require(
          accessibilityElements(host).first { $0.role == "AXButton" && $0.label == label })
      }
      func scroll() throws -> NSScrollView {
        var pending = [host as NSView]
        while let view = pending.popLast() {
          if let scroll = view as? NSScrollView { return scroll }
          pending.append(contentsOf: view.subviews)
        }
        throw NSError(domain: "ScrollObservationTests", code: 1)
      }
      try await settle()
      let native = try scroll()
      let initialOrigin = native.contentView.bounds.origin
      func move(_ offset: Double) async throws {
        native.contentView.scroll(
          to: horizontal
            ? CGPoint(x: rtl ? (initialOrigin.x - offset) : offset, y: 0) : CGPoint(x: 0, y: offset)
        )
        native.reflectScrolledClipView(native.contentView)
        try await settle()
      }
      try await move(200)
      #expect(hasText("Observed: 200; travel: 200"), "\(modelText())")
      try await move(160)
      #expect(hasText("Observed: 160; travel: 160"))
      #expect(try button("Disable notifications").press())
      try await settle()
      try await move(300)
      #expect(hasText("Observed: 160; travel: 160"))
      #expect(try scroll() === native)
      #expect(try button("Enable notifications").press())
      try await settle()
      try await move(340)
      #expect(hasText("Observed: 340; travel: 200"), "\(modelText())")
      #expect(try scroll() === native)
      let observer = try #require(session.tree.nodes.values.compactMap(\.scrollObserver).first)
      let generation = observer.generation
      session.isVisible = false
      #expect(!observer.observe(500, generation: generation))
      session.isVisible = true
      try await settle()
      #expect(!observer.observe(500, generation: generation))
      try await move(380)
      #expect(hasText("Observed: 380; travel: 240"), "\(modelText())")
      let resumed = observer.generation
      await session.close()
      #expect(!observer.observe(600, generation: resumed))
    } catch {
      await session.close()
      throw error
    }
  }
}

@MainActor struct ScrollObserverTests {
  @Test func phaseBoundariesFlushTravelAndRetiredCallbacksCannotReport() {
    var events: [NativeEventPayload] = []
    let observer = ScrollObserver(vertical: true, handler: 1) {
      events.append($0)
      return true
    }
    observer.attach()
    observer.setPresented(true)
    let initial = observer.generation
    #expect(observer.observe(100, generation: initial))
    #expect(events.isEmpty)
    #expect(observer.observe(123, generation: initial))
    #expect(observer.phase(124, generation: initial))
    #expect(observer.observe(120, generation: initial))
    #expect(
      events == [
        .scroll(pixels: 123, delta: 23), .scroll(pixels: 124, delta: 1),
        .scroll(pixels: 124, delta: 0), .scroll(pixels: 120, delta: -4),
      ])
    for invalid in [Double.nan, .infinity, -.infinity] {
      #expect(!observer.observe(invalid, generation: initial))
      #expect(!observer.phase(invalid, generation: initial))
    }
    observer.synchronize(vertical: false, handler: 2)
    observer.setPresented(true)
    #expect(!observer.phase(500, generation: initial))
    #expect(observer.observe(40, generation: observer.generation))
    #expect(observer.observe(45, generation: observer.generation))
    #expect(events.last == .scroll(pixels: 45, delta: 5))
    let rebound = observer.generation
    observer.detach()
    #expect(!observer.observe(100, generation: rebound))
    observer.attach()
    #expect(observer.observe(60, generation: observer.generation))
    #expect(observer.phase(60, generation: observer.generation))
    #expect(events.last == .scroll(pixels: 60, delta: 0))
    observer.dispose()
    observer.attach()
    observer.setPresented(true)
    #expect(!observer.phase(70, generation: observer.generation))
  }

  @Test func disabledAndHiddenIntervalsDoNotBecomeTravel() {
    var events: [NativeEventPayload] = []
    let observer = ScrollObserver(vertical: true, handler: nil) {
      events.append($0)
      return true
    }
    observer.attach()
    observer.setPresented(true)
    #expect(!observer.observe(100, generation: observer.generation))
    observer.synchronize(vertical: true, handler: 1)
    observer.setPresented(true)
    #expect(observer.observe(120, generation: observer.generation))
    #expect(observer.observe(130, generation: observer.generation))
    observer.setPresented(false)
    #expect(!observer.observe(300, generation: observer.generation))
    observer.setPresented(true)
    #expect(observer.observe(320, generation: observer.generation))
    #expect(observer.observe(324, generation: observer.generation))
    #expect(events == [.scroll(pixels: 130, delta: 10), .scroll(pixels: 324, delta: 4)])
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nestedScrollObserversKeepTheirSourcesAndReportBackpressure() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-scroll-observer-nested")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { _ = session.activate($0) }))
      host.sizingOptions = []
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 640, height: 540),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func settle() async throws {
        for _ in 0..<3 {
          _ = try await session.refresh()
          if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
          try await settleAccessibility(host)
        }
      }
      func texts() -> [String] {
        session.tree.nodes.values.compactMap {
          if case .text(let value) = $0.properties { return value.value }
          return nil
        }
      }
      try await settle()
      var pending: [NSView] = [host]
      var scrolls: [NSScrollView] = []
      while let view = pending.popLast() {
        if let scroll = view as? NSScrollView { scrolls.append(scroll) }
        pending.append(contentsOf: view.subviews)
      }
      #expect(scrolls.count == 2)
      let outer = try #require(scrolls.first { ($0.documentView?.frame.height ?? 0) > 1000 })
      let inner = try #require(scrolls.first { $0 !== outer })
      outer.contentView.scroll(to: CGPoint(x: 0, y: 80))
      outer.reflectScrolledClipView(outer.contentView)
      try await settle()
      #expect(texts().contains("Outer: 80; travel: 80"))
      #expect(texts().contains("Observed: 0; travel: 0"))
      inner.contentView.scroll(to: CGPoint(x: 120, y: 0))
      inner.reflectScrolledClipView(inner.contentView)
      try await settle()
      #expect(texts().contains("Outer: 80; travel: 80"))
      #expect(texts().contains("Observed: 120; travel: 120"))
      let observer = try #require(
        session.tree.nodes.values.compactMap(\.scrollObserver).first { $0.vertical })
      for _ in 0..<1024 { #expect(observer.phase(80, generation: observer.generation)) }
      #expect(!observer.phase(80, generation: observer.generation))
      do {
        _ = try await session.refresh()
        Issue.record("A full scroll event queue did not fail the session")
      } catch {
        #expect(error as? WireError == .limitExceeded)
      }
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension ScrollObserverTests {
  @Test func scrollBindingsDoNotRelaxOtherNodeContracts() throws {
    func bindings(_ tags: [Int]) -> WireOperation {
      TreeFixture.operation(OperationId.updateEventBindings) {
        $0.integer(UInt64(1))
        $0.integer(UInt16(tags.count))
        for tag in tags {
          $0.integer(UInt16(tag))
          $0.integer(UInt64(tag + 1))
        }
      }
    }
    let roots: [([WireOperation], [Int])] = [
      (
        [
          TreeFixture.scroll(), TreeFixture.text(2, "Row"), TreeFixture.children(1, [2]),
          TreeFixture.root(1),
        ], []
      ),
      (TreeFixture.sectionsTree(), []),
      (TreeFixture.scrollTargetTree(), [55]),
      (
        [
          TreeFixture.collection(), TreeFixture.collectionWindow(first: 0, keys: []),
          TreeFixture.children(1, [2]), TreeFixture.root(1),
        ], [14]
      ),
    ]
    for (operations, required) in roots {
      let store = try NodeStore().staging(TreeFixture.frame(operations)).tree
      let bound = try store.staging(
        TreeFixture.frame([bindings(required + [13])], base: 1, revision: 2)
      ).tree
      #expect(bound.nodes[1]?.bindings[13] == 14)
      _ = try bound.staging(TreeFixture.frame([bindings(required)], base: 2, revision: 3))
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([bindings(required + [1])], base: 1, revision: 2))
      }
      if !required.isEmpty {
        #expect(throws: (any Error).self) {
          try store.staging(TreeFixture.frame([bindings([13])], base: 1, revision: 2))
        }
      }
      #expect(store.revision == 1)
    }
    let plain = try NodeStore().staging(TreeFixture.initial).tree
    #expect(throws: (any Error).self) {
      try plain.staging(TreeFixture.frame([bindings([13])], base: 1, revision: 2))
    }
  }
}
