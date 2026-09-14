import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func controlSize(_ id: UInt64, _ size: UInt8, update: Bool = false) -> WireOperation {
    modifier(id, kind: 55, mask: 1, update: update) { $0.integer(size) }
  }
  static func sizedButton(_ size: UInt8) -> [WireOperation] {
    [
      controlSize(1, size), button(2, role: 0, style: 2), text(3, "Action"),
      children(1, [2]), children(2, [3]), root(1),
    ]
  }
}

@MainActor struct ControlSizeTests {
  @Test func sizesMatchNativeControlsAndNestedScopesOverrideTheParent() async throws {
    initializeAccessibilityApplication()
    let sizes: [ControlSize] = [.mini, .small, .regular, .large, .extraLarge]
    var heights: [CGFloat] = []
    func measure<V: View>(_ view: V) async throws -> CGSize {
      let host = NSHostingView(rootView: view)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      return host.fittingSize
    }
    for (index, size) in sizes.enumerated() {
      let tree = RenderTree()
      tree.commit(
        try NodeStore().staging(TreeFixture.frame(TreeFixture.sizedButton(UInt8(index)))).tree)
      let actual = try await measure(NativeNodeView(node: #require(tree.root), activate: { _ in }))
      let label = try #require(tree.nodes[3])
      let reference = Button {
      } label: {
        NativeNodeView(node: label, activate: { _ in })
      }
      .buttonStyle(.bordered).controlSize(size)
      let expected = try await measure(reference)
      #expect(abs(actual.height - expected.height) < 0.5)
      #expect(abs(actual.width - expected.width) < 0.5)
      heights.append(actual.height)
      let nested = try treeSnapshot(size: UInt8(index), inner: 0)
      let nestedTree = RenderTree()
      nestedTree.commit(nested)
      let overridden = try await measure(
        NativeNodeView(node: #require(nestedTree.root), activate: { _ in }))
      #expect(abs(overridden.height - heights[0]) < 0.5)
    }
    #expect(try #require(heights.last) > #require(heights.first))
  }

  private func treeSnapshot(size: UInt8, inner: UInt8) throws -> NodeStore {
    try NodeStore().staging(
      TreeFixture.frame(
        TreeFixture.sizedButton(size) + [
          TreeFixture.controlSize(4, inner), TreeFixture.children(4, [2]),
          TreeFixture.children(1, [4]),
        ])
    ).tree
  }

  @Test func invalidScopesCannotPublishPartialUpdates() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.sizedButton(2))).tree
    for operation in [
      TreeFixture.controlSize(1, 5, update: true), TreeFixture.children(1, []),
      TreeFixture.children(1, [2, 3]),
    ] {
      #expect(throws: (any Error).self) {
        try initial.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
    let update = TreeFixture.controlSize(1, 4, update: true)
    for count in 0..<update.body.count {
      #expect(throws: (any Error).self) {
        try initial.staging(
          TreeFixture.frame(
            [
              WireOperation(opcode: update.opcode, body: update.body.prefix(count))
            ], base: 1, revision: 2))
      }
    }
    #expect(initial.revision == 1)
  }
}
