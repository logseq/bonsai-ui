import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor struct DividerTests {
  @Test func dividerFollowsNativeParentOrientationAndAppearance() throws {
    for kind in [NodeKindId.row, NodeKindId.column, NodeKindId.stack] {
      let model = RenderTree()
      model.commit(
        try NodeStore().staging(
          TreeFixture.frame([
            TreeFixture.create(1, kind: kind), TreeFixture.create(2, kind: NodeKindId.divider),
            TreeFixture.children(1, [2]), TreeFixture.root(1),
          ])
        ).tree)
      let root = try #require(model.root)
      let expected = Group {
        if kind == NodeKindId.row {
          HStack { Divider() }
        } else if kind == NodeKindId.column {
          VStack { Divider() }
        } else {
          ZStack { Divider() }
        }
      }
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        for scheme in [ColorScheme.light, .dark] {
          #expect(
            try raster(
              NativeNodeView(node: root, activate: { _ in })
                .frame(width: 180, height: 70).environment(\.colorScheme, scheme), direction
            )
            .matches(
              raster(
                expected.frame(width: 180, height: 70)
                  .environment(\.colorScheme, scheme), direction)))
        }
      }
    }
  }

  @Test func dividerRetainsIdentityWhenReorderedOrItsPaddingChanges() throws {
    let before = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.create(1, kind: NodeKindId.column),
        TreeFixture.create(2, kind: NodeKindId.divider),
        TreeFixture.padding(3, leading: 8, top: 4, trailing: 12, bottom: 6),
        TreeFixture.text(4, "Native"), TreeFixture.children(3, [2]),
        TreeFixture.children(1, [4, 3]), TreeFixture.root(1),
      ])
    ).tree
    let model = RenderTree()
    model.commit(before)
    let divider = try #require(model.nodes[2])
    let next = try before.staging(
      TreeFixture.frame(
        [
          TreeFixture.padding(3, leading: 16, top: 2, trailing: 0, bottom: 3, update: true),
          TreeFixture.children(1, [3, 4]),
        ], base: 1, revision: 2)
    ).tree
    model.commit(next)
    #expect(model.nodes[2] === divider)
    let expected = VStack(spacing: 16) {
      Divider().padding(EdgeInsets(top: 2, leading: 16, bottom: 3, trailing: 0))
      Text("Native").font(.system(size: 17))
    }
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      #expect(
        try raster(
          NativeNodeView(node: try #require(model.root), activate: { _ in })
            .frame(width: 180, height: 70), direction
        )
        .matches(raster(expected.frame(width: 180, height: 70), direction)))
    }
  }

  @Test func dividerRejectsOldGeometryBindingsAndChildrenAtomically() throws {
    let before = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.create(1, kind: NodeKindId.divider), TreeFixture.root(1),
      ])
    ).tree
    let oldPayload = TreeFixture.operation(OperationId.updateProps) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(NodeKindId.divider))
      $0.integer(UInt64(31))
      $0.integer(UInt8(0))
      for value in [1.0, 16, 0, 0] { $0.integer(value.bitPattern) }
    }
    let binding = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(1))
      $0.integer(UInt16(EventTagId.press))
      $0.integer(UInt64(9))
    }
    for operations in [
      [oldPayload], [binding],
      [TreeFixture.text(2, "Invalid"), TreeFixture.children(1, [2])],
    ] {
      #expect(throws: (any Error).self) {
        try before.staging(TreeFixture.frame(operations, base: 1, revision: 2))
      }
      #expect(before.revision == 1 && before.nodes.count == 1)
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryDividersUseNativeRowAndColumnSeparators() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "gallery-dividers")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      #expect(state.tree.nodes.values.filter { $0.kind == NodeKindId.divider }.count == 3)
      let model = RenderTree()
      model.commit(state.tree)
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        let rendered = try raster(
          NativeNodeView(node: try #require(model.root), activate: { _ in })
            .padding(24).frame(width: 360).fixedSize(horizontal: false, vertical: true), direction)
        #expect(rendered.width == 376 && rendered.height > 180)
        if let path = ProcessInfo.processInfo.environment["BONSAI_RENDER_ARTIFACT_DIRECTORY"] {
          try rendered.write(
            to: URL(fileURLWithPath: path).appendingPathComponent(
              "gallery-dividers-\(direction == .leftToRight ? "ltr" : "rtl").png"))
        }
      }
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
