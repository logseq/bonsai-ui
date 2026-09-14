import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func hostWindowPresentsCounterAndClosesWhenRemoved() async throws {
    _ = NSApplication.shared
    let session = BonsaiSession()
    let host = NSHostingView(
      rootView: AnyView(
        BonsaiApplicationView(entrypoint: "counter", session: session)
          .environment(\.scenePhase, .active)))
    let window = NSWindow(
      contentRect: NSRect(x: 120, y: 120, width: 360, height: 240),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    do {
      for _ in 0..<150 where session.displayedRevision == 0 {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(session.displayedRevision > 0)
      #expect(window.title == "Counter")
      let button = try #require(session.tree.nodes.values.first { $0.kind == NodeKindId.button })
      #expect(session.activate(button))
      for _ in 0..<150 where session.displayedRevision < 2 {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(session.tree.nodes.values.contains { $0.properties == .text("Count: 1") })
      #expect(session.displayedRevision >= 2)
      host.rootView = AnyView(EmptyView())
      for _ in 0..<150 where session.tree.root != nil {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(session.tree.root == nil)
      window.close()
      await session.close()
    } catch {
      window.close()
      await session.close()
      throw error
    }
  }

  @Test @MainActor func sessionWaitsForPresentationAndDispatchesVisibleButton() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "counter")
      let initial = try #require(session.ticket)
      #expect(session.displayedRevision == 0)
      #expect(try await session.refresh() == false)
      let button = try #require(session.tree.nodes.values.first { $0.kind == NodeKindId.button })
      #expect(session.activate(button) == false)
      #expect(try await session.presented(initial))
      #expect(session.displayedRevision == initial.revision)
      #expect(session.activate(button))
      #expect(try await session.refresh())
      let updated = try #require(session.ticket)
      #expect(session.tree.nodes.values.contains { $0.properties == .text("Count: 1") })
      #expect(session.displayedRevision == initial.revision)
      #expect(try await session.presented(initial) == false)
      #expect(session.ticket == updated)
      #expect(try await session.presented(updated))
      await session.close()
      #expect(session.tree.root == nil)
      #expect(session.ticket == nil)
      try await session.start(entrypoint: "counter")
      let restarted = try #require(session.ticket)
      #expect(restarted.session != updated.session)
      #expect(try await session.presented(updated) == false)
      #expect(try await session.presented(restarted))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }

  @Test @MainActor func hiddenSessionDefersPumpAndPresentationWithoutLosingEvents() async throws {
    let session = BonsaiSession()
    do {
      try await session.start(entrypoint: "counter")
      #expect(session.tree.root == nil)
      session.isVisible = true
      #expect(try await session.refresh())
      let initial = try #require(session.ticket)
      session.isVisible = false
      #expect(try await session.presented(initial) == false)
      #expect(session.ticket == initial)
      session.isVisible = true
      #expect(try await session.presented(initial))
      let button = try #require(session.tree.nodes.values.first { $0.kind == NodeKindId.button })
      #expect(session.activate(button))
      #expect(session.activate(button))
      async let first = session.refresh()
      async let second = session.refresh()
      let results = try await [first, second]
      #expect(results.filter { $0 }.count == 1)
      #expect(session.tree.nodes.values.contains { $0.properties == .text("Count: 2") })
      let updated = try #require(session.ticket)
      #expect(try await session.presented(updated))
      #expect(try await session.refresh() == false)
      #expect(session.ticket == nil)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
