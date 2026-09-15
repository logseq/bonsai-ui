import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test(arguments: [0, 1, 2], [(false, false), (false, true), (true, false), (true, true)])
  @MainActor
  func actualInitialScrollPositionsAreExplicitAndDoNotReplay(kind: Int, layout: (Bool, Bool))
    async throws
  {
    let (horizontal, rtl) = layout
    initializeAccessibilityApplication()
    for initial in 0..<(kind == 2 ? 3 : 2) {
      let session = BonsaiSession()
      session.isVisible = true
      do {
        try await session.start(
          entrypoint: "native-initial-\(kind)-\(horizontal ? "h" : "v")-\(initial)")
        let host = NSHostingView(
          rootView: NativeNodeView(
            node: try #require(session.tree.root),
            activate: { _ = session.activate($0) }
          ).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
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
          for _ in 0..<4 {
            _ = try await session.refresh()
            if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
            try await settleAccessibility(host)
          }
        }
        func button(_ label: String) throws -> AccessibilityElement {
          try #require(
            accessibilityElements(host).first { $0.role == "AXButton" && $0.label == label })
        }
        func scroll() throws -> NSScrollView {
          var pending: [NSView] = [host]
          while let view = pending.popLast() {
            if let scroll = view as? NSScrollView { return scroll }
            pending.append(contentsOf: view.subviews)
          }
          throw NSError(domain: "InitialScrollTests", code: 1)
        }
        try await settle()
        let native = try scroll()
        func leading() -> Double {
          horizontal
            ? (rtl
              ? native.documentView!.frame.width - native.contentView.bounds.width
                - native.contentView.bounds.minX : native.contentView.bounds.minX)
            : native.contentView.bounds.minY
        }
        let visibleExtent =
          horizontal ? native.contentView.bounds.width : native.contentView.bounds.height
        let total = kind == 2 ? 400040.0 : 4000.0
        let expected = initial == 0 ? 0 : initial == 1 ? total - visibleExtent : 300040
        #expect(
          abs(leading() - expected) < 1,
          "kind=\(kind), initial=\(initial), offset=\(leading()), expected=\(expected)")
        if kind == 2 {
          let first = initial == 0 ? 0 : initial == 1 ? Int((expected - 40) / 40) : 7500
          #expect(
            session.tree.nodes.values.contains {
              if case .text(let value) = $0.properties { return value.value == "Item \(first)" }
              return false
            })
          #expect(
            session.tree.nodes.values.contains {
              if case .text(let value) = $0.properties {
                return value.value == "First visible: \(first)"
              }
              return false
            })
          #expect(session.tree.nodes.count < 200)
        }
        #expect(try button("Change initial position").press())
        try await settle()
        #expect(abs(leading() - expected) < 1)
        native.contentView.scroll(
          to: horizontal
            ? CGPoint(
              x: rtl
                ? native.documentView!.frame.width - native.contentView.bounds.width - 200 : 200,
              y: 0)
            : CGPoint(x: 0, y: 200))
        native.reflectScrolledClipView(native.contentView)
        try await settle()
        #expect(abs(leading() - 200) < 1)
        #expect(try button("Change initial position").press())
        try await settle()
        #expect(abs(leading() - 200) < 1)
        #expect(try scroll() === native)
        #expect(try button("Append content").press())
        try await settle()
        #expect(abs(leading() - 200) < 1)
        window.setContentSize(CGSize(width: 720, height: 620))
        try await settle()
        #expect(abs(leading() - 200) < 1)
        #expect(try scroll() === native)
        session.isVisible = false
        session.isVisible = true
        try await settle()
        #expect(abs(leading() - 200) < 1)
        await session.close()
      } catch {
        await session.close()
        throw error
      }
    }
  }
}

@MainActor struct InitialScrollNodeTests {
  @Test func initialCollectionMetadataDoesNotInterruptGeometryAnimation() throws {
    func catalog(initial: UInt8, key: String? = nil, expanded: Bool = false, update: Bool = false)
      -> WireOperation
    {
      TreeFixture.collection(
        overrides: expanded ? [(1, 120)] : [], expandMilliseconds: 1000,
        initial: initial, initialKey: key, update: update)
    }
    var store = try NodeStore().staging(
      TreeFixture.frame([
        catalog(initial: 2, key: "b"), TreeFixture.collectionWindow(first: 0, keys: []),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree()
    tree.commit(store)
    let controller = try #require(tree.root?.collectionController)
    let viewport = controller.viewport
    #expect(viewport.position.y == 40)
    let attachmentID = UUID()
    viewport.attach(id: attachmentID)
    viewport.observe(CGRect(x: 0, y: 40, width: 100, height: 40))
    store = try store.staging(
      TreeFixture.frame(
        [catalog(initial: 2, key: "b", expanded: true, update: true)], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    let generation = viewport.animationID
    store = try store.staging(
      TreeFixture.frame([catalog(initial: 1, expanded: true, update: true)], base: 2, revision: 3)
    ).tree
    tree.commit(store)
    #expect(tree.root?.collectionController === controller)
    #expect(viewport.animationID == generation)
    #expect(viewport.leadingOffset == 40 && viewport.position.y == 40)
    viewport.finishAnimation()
    #expect(viewport.geometry.extent(at: 1) == 120)
    #expect(viewport.leadingOffset == 40)
    viewport.detach(id: attachmentID)
  }

  @Test func malformedInitialPositionsAndRetiredMasksCannotPublish() throws {
    let collection = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.collection(), TreeFixture.collectionWindow(first: 0, keys: []),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    for update in [
      TreeFixture.collection(initial: 3, update: true),
      TreeFixture.collection(initialKey: "a", update: true),
      TreeFixture.collection(initial: 1, initialKey: "a", update: true),
      TreeFixture.collection(initial: 2, update: true),
      TreeFixture.collection(initial: 2, initialKey: "missing", update: true),
    ] {
      #expect(throws: (any Error).self) {
        try collection.staging(TreeFixture.frame([update], base: 1, revision: 2))
      }
    }
    let scroll = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.scroll(), TreeFixture.text(2, "Content"), TreeFixture.children(1, [2]),
        TreeFixture.root(1),
      ])
    ).tree
    let sections = try NodeStore().staging(TreeFixture.frame(TreeFixture.sectionsTree())).tree
    for (store, update, mask) in [
      (scroll, TreeFixture.scroll(update: true), UInt64(7)),
      (sections, TreeFixture.scrollSections(update: true), UInt64(31)),
      (collection, TreeFixture.collection(update: true), UInt64(127)),
    ] {
      var retired = update.body
      retired.replaceSubrange(
        10..<18, with: (0..<8).map { UInt8(truncatingIfNeeded: mask >> ($0 * 8)) })
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [WireOperation(opcode: OperationId.updateProps, body: retired)], base: 1, revision: 2))
      }
    }
    #expect(throws: (any Error).self) {
      try scroll.staging(
        TreeFixture.frame([TreeFixture.scroll(initial: 2, update: true)], base: 1, revision: 2))
    }
    #expect(throws: (any Error).self) {
      try sections.staging(
        TreeFixture.frame(
          [TreeFixture.scrollSections(initial: 2, update: true)], base: 1, revision: 2))
    }
    #expect(collection.revision == 1 && scroll.revision == 1 && sections.revision == 1)
  }
}
