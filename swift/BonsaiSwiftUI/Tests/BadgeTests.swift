import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func badge(
    _ id: UInt64 = 1, count: UInt64? = nil, alignment: UInt8 = 2,
    visible: UInt8 = 1, update: Bool = false, bound: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(58))
      if update { $0.integer(UInt64(7)) }
      $0.integer(UInt8(count == nil ? 0 : 1))
      if let count { $0.integer(count) }
      $0.integer(alignment)
      $0.integer(visible)
      if !update {
        $0.integer(UInt16(bound ? 1 : 0))
        if bound {
          $0.integer(UInt16(EventTagId.press))
          $0.integer(UInt64(91))
        }
      }
    }
  }
  static func badgeTree(_ badge: WireOperation = badge()) -> [WireOperation] {
    [badge, text(2, "Inbox"), children(1, [2]), root(1)]
  }
}

@MainActor struct BadgeTests {
  @Test(arguments: [false, true], [UInt8(0), 1, 2])
  func numericAndDotOverlaysFollowNativeAlignmentWithoutSizingContent(rtl: Bool, alignment: UInt8)
    throws
  {
    for count: UInt64? in [nil, 0, 8, UInt64(Int64.max)] {
      let tree = RenderTree()
      tree.commit(
        try NodeStore().staging(
          TreeFixture.frame(
            TreeFixture.badgeTree(TreeFixture.badge(count: count, alignment: alignment)))
        ).tree)
      let decoration: AnyView
      if let count {
        decoration = AnyView(
          Text(String(count)).font(.caption2.weight(.semibold))
            .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
            .background(.red, in: Capsule()).fixedSize())
      } else {
        decoration = AnyView(Circle().fill(.red).frame(width: 8, height: 8))
      }
      let reference = Text("Inbox").font(.system(size: 17)).overlay(
        alignment: [.topLeading, .top, .topTrailing][Int(alignment)]
      ) {
        decoration.alignmentGuide(.top) { $0.height / 2 }
          .alignmentGuide(.leading) { $0.width / 2 }.alignmentGuide(.trailing) { $0.width / 2 }
          .allowsHitTesting(false).accessibilityHidden(true)
      }
      let actual = NativeNodeView(node: try #require(tree.root), activate: { _ in })
      #expect(
        try raster(actual.padding(80), rtl ? .rightToLeft : .leftToRight).matches(
          raster(reference.padding(80), rtl ? .rightToLeft : .leftToRight)))
    }
  }
  @Test func hiddenDecorationLeavesContentVisibleAndMalformedUpdatesAreAtomic() throws {
    let original = try NodeStore().staging(
      TreeFixture.frame(TreeFixture.badgeTree(TreeFixture.badge(count: 0, visible: 0)))
    ).tree
    let tree = RenderTree()
    tree.commit(original)
    #expect(
      try raster(NativeNodeView(node: #require(tree.root), activate: { _ in })).matches(
        raster(Text("Inbox").font(.system(size: 17)))))
    let change = TreeFixture.badge(count: 42, update: true)
    var invalid = [
      TreeFixture.badge(count: UInt64.max, update: true),
      TreeFixture.badge(alignment: 3, update: true), TreeFixture.badge(visible: 2, update: true),
      TreeFixture.children(1, []), TreeFixture.children(1, [2, 2]),
    ]
    for count in 0..<change.body.count {
      invalid.append(WireOperation(opcode: change.opcode, body: change.body.prefix(count)))
    }
    invalid.append(WireOperation(opcode: change.opcode, body: change.body + Data([0])))
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try original.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Must not leak", update: true), operation], base: 1, revision: 2))
      }
      #expect(original.revision == 1)
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame(TreeFixture.badgeTree(TreeFixture.badge(bound: true))))
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualBadgeUpdatesRetainContentAndDisabledOwnership() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func named(_ text: String, in node: RenderNodeState) -> Bool {
      if case .text(let value) = node.properties, value.value == text { return true }
      return node.children.contains { named(text, in: $0) }
    }
    func button(_ text: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          if case .button = $0.properties { return named(text, in: $0) }
          return false
        })
    }
    func press(_ text: String) async throws {
      #expect(session.activate(try button(text)))
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    do {
      try await session.start(entrypoint: "native-badges")
      let content = try button("Open notifications")
      #expect(!session.activate(content))
      #expect(try await session.presented(#require(session.ticket)))
      for control in [
        "Maximum badge", "Dot badge", "Zero badge", "Increment badge", "Hide badge", "Move badge",
        "Show badge",
      ] {
        try await press(control)
        #expect(try button("Open notifications") === content)
      }
      try await press("Hide badge")
      try await press("Open notifications")
      #expect(named("Badge actions: 1", in: try #require(session.tree.root)))
      try await press("Disable content")
      #expect(!session.activate(content))
      try await press("Enable content")
      try await press("Open notifications")
      #expect(named("Badge actions: 2", in: try #require(session.tree.root)))
      await session.close()
      #expect(!session.activate(content))
    } catch {
      await session.close()
      throw error
    }
  }
}
