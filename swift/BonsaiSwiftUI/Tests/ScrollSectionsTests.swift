import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func scrollSections(
    vertical: Bool = true, spacing: Double = 0, initial: UInt8 = 0, update: Bool = false
  )
    -> WireOperation
  {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(75))
      if update { $0.integer(UInt64(63)) }
      $0.integer(UInt8(vertical ? 1 : 0))
      $0.integer(UInt8(1))
      $0.integer(UInt8(1))
      $0.integer(spacing.bitPattern)
      $0.integer(UInt8(1))
      $0.integer(initial)
      if !update { $0.integer(UInt16(0)) }
    }
  }
  static func scrollSection(
    _ id: UInt64, header: Bool = true, footer: Bool = true,
    hero: Double? = nil, stretch: Bool = false, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(76))
      if update { $0.integer(UInt64(15)) }
      $0.integer(UInt8(header ? 1 : 0))
      $0.integer(UInt8(footer ? 1 : 0))
      $0.integer(UInt8(hero == nil ? 0 : 1))
      if let hero { $0.integer(hero.bitPattern) }
      $0.integer(UInt8(stretch ? 1 : 0))
      if !update { $0.integer(UInt16(0)) }
    }
  }
  static func sectionsTree() -> [WireOperation] {
    [
      scrollSections(), scrollSection(2, header: false, footer: false, hero: 160, stretch: true),
      text(3, "Unused"), text(4, "Unused"), text(5, "Hero"), children(2, [3, 4, 5]),
      scrollSection(6), text(7, "Header"), text(8, "Footer"), text(9, "First"), text(10, "Second"),
      children(6, [7, 8, 9, 10]), children(1, [2, 6]), root(1),
    ]
  }
}

@MainActor struct ScrollSectionsTests {
  @Test func sectionsRetainHeadersFootersAndReorderedRows() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.sectionsTree())).tree
    let tree = RenderTree()
    tree.commit(initial)
    let originals = tree.nodes
    let next = try initial.staging(
      TreeFixture.frame(
        [
          TreeFixture.scrollSection(
            2, header: false, footer: false, hero: 200, stretch: false, update: true),
          TreeFixture.children(6, [7, 8, 10, 9]),
          TreeFixture.text(7, "Updated header", update: true),
        ], base: 1, revision: 2)
    ).tree
    tree.commit(next)
    #expect(originals.allSatisfy { tree.nodes[$0.key] === $0.value })
    #expect(tree.nodes[6]?.children.map(\.id.node) == [7, 8, 10, 9])
  }

  @Test func sectionFramingAndOwnershipAreAtomic() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.sectionsTree())).tree
    let malformed: [WireOperation] = [
      TreeFixture.scrollSections(spacing: -1, update: true),
      TreeFixture.scrollSections(spacing: .nan, update: true),
      TreeFixture.scrollSection(2, header: false, footer: false, hero: 0, update: true),
      TreeFixture.scrollSection(2, header: false, footer: false, hero: .infinity, update: true),
      TreeFixture.scrollSection(2, header: true, footer: false, hero: 160, update: true),
      TreeFixture.scrollSection(6, stretch: true, update: true),
    ]
    for operation in malformed {
      #expect(throws: TreeError.invalidProperties) {
        _ = try initial.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
    for operation in [
      TreeFixture.scrollSections(update: true), TreeFixture.scrollSection(6, update: true),
    ] {
      for length in 0..<operation.body.count {
        #expect(throws: (any Error).self) {
          _ = try initial.staging(
            TreeFixture.frame(
              [
                WireOperation(opcode: operation.opcode, body: operation.body.prefix(length))
              ], base: 1, revision: 2))
        }
      }
    }
    for operations in [
      [TreeFixture.scrollSections(vertical: false, update: true)],
      [TreeFixture.children(1, [6, 2])],
      [TreeFixture.root(6)],
      [TreeFixture.children(6, [7])],
      [TreeFixture.children(1, [2, 7, 6])],
    ] {
      #expect(throws: (any Error).self) {
        _ = try initial.staging(TreeFixture.frame(operations, base: 1, revision: 2))
      }
    }
    #expect(initial.nodes[6]?.children == [7, 8, 9, 10])
  }
}

extension NativeRuntimeTests {
  @Test(arguments: [false, true], [false, true]) @MainActor
  func actualSectionsPinNativeControlsAndRetainTheirIdentity(horizontal: Bool, rightToLeft: Bool)
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(
        entrypoint: horizontal ? "native-sections-horizontal" : "native-sections")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root),
          activate: { _ = session.activate($0) }
        )
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
      host.sizingOptions = []
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 720, height: 540),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func settle() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
        try await settleAccessibility(host)
      }
      func element(_ label: String) throws -> AccessibilityElement {
        try #require(
          accessibilityElements(host).first { $0.role == "AXButton" && $0.label == label })
      }
      func rect(_ label: String) throws -> CGRect {
        let object = try element(label).object
        let selector = NSSelectorFromString("accessibilityFrame")
        #expect(object.responds(to: selector))
        typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
      }
      func scroll() throws -> NSScrollView {
        var pending: [NSView] = [host]
        while let view = pending.popLast() {
          if let scroll = view as? NSScrollView { return scroll }
          pending.append(contentsOf: view.subviews)
        }
        throw NSError(domain: "ScrollSectionsTests", code: 1)
      }
      func text(_ value: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == value }
          return false
        }
      }
      func hasLabel(_ node: RenderNodeState, _ label: String) -> Bool {
        if case .text(let text) = node.properties, text.value == label { return true }
        return node.children.contains { hasLabel($0, label) }
      }
      func button(_ label: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first { $0.kind == NodeKindId.button && hasLabel($0, label) })
      }
      try await settle()
      let native = try scroll()
      let header = try button("Header A")
      let originals = session.tree.nodes
      if !horizontal {
        let before = try rect("Hero action")
        #expect(try element("Resize hero").press())
        try await settle()
        let after = try rect("Hero action")
        #expect(
          abs(after.height - before.height - 40) < 1, "Hero before: \(before), after: \(after)")
        #expect(try element("Toggle stretch").press())
        try await settle()
        #expect(text("Stretch: off"))
      }
      let x =
        rightToLeft
        ? try #require(native.documentView).frame.width - native.contentView.bounds.width - 220
        : 220
      native.contentView.scroll(to: horizontal ? CGPoint(x: x, y: 0) : CGPoint(x: 0, y: 280))
      native.reflectScrolledClipView(native.contentView)
      try await settle()
      let clip = window.convertToScreen(
        native.contentView.convert(native.contentView.bounds, to: nil))
      let headerRect = try rect("Header A")
      let footerRect = try rect("Footer A")
      if horizontal {
        if rightToLeft {
          #expect(abs(headerRect.maxX - clip.maxX) < 2)
          #expect(abs(footerRect.minX - clip.minX) < 2)
        } else {
          #expect(abs(headerRect.minX - clip.minX) < 2)
          #expect(abs(footerRect.maxX - clip.maxX) < 2)
        }
      } else {
        #expect(abs(headerRect.maxY - clip.maxY) < 2)
        #expect(abs(footerRect.minY - clip.minY) < 2)
      }
      #expect(try element("Header A").press())
      #expect(try element("Footer A").press())
      try await settle()
      #expect(text("Section actions: 2"))
      #expect(try element("Reverse rows").press())
      try await settle()
      #expect(originals.allSatisfy { session.tree.nodes[$0.key] === $0.value })
      #expect(try scroll() === native)
      #expect(session.activate(try button("Toggle pinning")))
      _ = try await session.refresh()
      #expect(!session.activate(header))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.activate(try button("Toggle pinning")))
      try await settle()
      #expect(try element("Hide headers").press())
      try await settle()
      #expect(!session.activate(header))
      #expect(try element("Show headers").press())
      try await settle()
      #expect(!session.activate(header))
      window.setContentSize(CGSize(width: 800, height: 620))
      try await settle()
      #expect(try scroll() === native)
      let freshHeader = try button("Header A")
      session.isVisible = false
      #expect(!session.activate(freshHeader))
      await session.close()
      #expect(!session.activate(freshHeader))
    } catch {
      await session.close()
      throw error
    }
  }
}
