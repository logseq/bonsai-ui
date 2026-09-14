import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func scroll(
    _ id: UInt64 = 1, vertical: UInt8 = 1, indicators: UInt8 = 1, fill: UInt8 = 0,
    initial: UInt8 = 0,
    update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(9))
      if update { $0.integer(UInt64(15)) }
      $0.integer(vertical)
      $0.integer(indicators)
      $0.integer(fill)
      $0.integer(initial)
      if !update { $0.integer(UInt16(0)) }
    }
  }
}

struct ScrollNodeTests {
  @Test func scrollPropertiesAndSingleChildValidateBeforePublication() throws {
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.scroll(), TreeFixture.text(2, "Content"),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    _ = try initial.staging(
      TreeFixture.frame(
        [TreeFixture.scroll(vertical: 0, indicators: 0, update: true)], base: 1, revision: 2))
    for invalid in [
      TreeFixture.scroll(vertical: 2, update: true),
      TreeFixture.scroll(indicators: 2, update: true),
      TreeFixture.scroll(fill: 2, update: true),
      TreeFixture.children(1, []),
      TreeFixture.children(1, [2, 2]),
    ] {
      #expect(throws: (any Error).self) {
        try initial.staging(TreeFixture.frame([invalid], base: 1, revision: 2))
      }
      #expect(initial.revision == 1)
    }
    var retired = TreeFixture.scroll(update: true).body
    retired.replaceSubrange(10..<18, with: [3, 0, 0, 0, 0, 0, 0, 0])
    #expect(throws: (any Error).self) {
      try initial.staging(
        TreeFixture.frame(
          [WireOperation(opcode: OperationId.updateProps, body: retired)], base: 1, revision: 2))
    }
    for kind in [30, 32, 33, 34, 35, 36, 37] {
      let retiredNode = TreeFixture.operation(OperationId.createNode) {
        $0.integer(UInt64(1))
        $0.integer(UInt16(kind))
        $0.integer(UInt16(0))
      }
      #expect(throws: TreeError.unsupportedNode(kind)) {
        try NodeStore().staging(TreeFixture.frame([retiredNode, TreeFixture.root(1)]))
      }
    }
    let update = TreeFixture.scroll(update: true)
    for length in 0..<update.body.count {
      #expect(throws: (any Error).self) {
        try initial.staging(
          TreeFixture.frame(
            [WireOperation(opcode: update.opcode, body: update.body.prefix(length))], base: 1,
            revision: 2))
      }
    }
  }
}

@MainActor private func nativeScrollViews(_ root: NSView) -> [NSScrollView] {
  (root as? NSScrollView).map { [$0] } ?? root.subviews.flatMap { nativeScrollViews($0) }
}
@MainActor private func settleScrolls(_ hosting: NSView) async throws {
  for _ in 0..<10 {
    hosting.layoutSubtreeIfNeeded()
    hosting.displayIfNeeded()
    try await Task.sleep(for: .milliseconds(10))
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryScrollsInBothAxesAndRetainsOffsetsThroughUpdates() async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-scroll")
      let hosting = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 380), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = hosting
      defer { window.contentView = nil }
      try await settleScrolls(hosting)
      let scrolls = nativeScrollViews(hosting)
      #expect(scrolls.count == 2)
      let vertical = try #require(scrolls.first { ($0.documentView?.frame.height ?? 0) > 500 })
      let horizontal = try #require(scrolls.first { ($0.documentView?.frame.width ?? 0) > 500 })
      #expect(abs((vertical.documentView?.frame.height ?? 0) - 800) < 1)
      #expect(abs((horizontal.documentView?.frame.width ?? 0) - 800) < 1)
      #expect(vertical.hasVerticalScroller)
      vertical.contentView.scroll(to: CGPoint(x: 0, y: 400))
      vertical.reflectScrolledClipView(vertical.contentView)
      horizontal.contentView.scroll(to: CGPoint(x: 300, y: 0))
      horizontal.reflectScrolledClipView(horizontal.contentView)
      try await settleScrolls(hosting)
      #expect(abs(vertical.documentVisibleRect.minY - 400) < 1)
      #expect(abs(horizontal.documentVisibleRect.minX - 300) < 1)
      #expect(try await session.presented(#require(session.ticket)))
      let button = try #require(session.tree.nodes.values.first { $0.kind == NodeKindId.button })
      #expect(session.activate(button))
      #expect(try await session.refresh())
      try await settleScrolls(hosting)
      #expect(nativeScrollViews(hosting).contains { $0 === vertical })
      #expect(nativeScrollViews(hosting).contains { $0 === horizontal })
      #expect(abs((vertical.documentView?.frame.height ?? 0) - 960) < 1)
      #expect(abs((horizontal.documentView?.frame.width ?? 0) - 1000) < 1)
      #expect(!vertical.hasVerticalScroller)
      #expect(abs(vertical.documentVisibleRect.minY - 400) < 1)
      #expect(abs(horizontal.documentVisibleRect.minX - 300) < 1)
      window.setContentSize(NSSize(width: 480, height: 380))
      try await settleScrolls(hosting)
      #expect(abs(vertical.documentVisibleRect.minY - 400) < 1)
      #expect(abs(horizontal.documentVisibleRect.minX - 300) < 1)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
