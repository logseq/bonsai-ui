import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func overlay(_ id: UInt64, alignment: UInt8 = 4, update: Bool = false) -> WireOperation {
    modifier(id, kind: NodeKindId.overlay, mask: 1, update: update) { $0.integer(alignment) }
  }
}

@MainActor struct OverlayTests {
  @Test func overlaysUseBaseMeasurementAndNativeAlignmentInBothDirections() throws {
    let alignments: [Alignment] = [
      .topLeading, .top, .topTrailing, .leading, .center, .trailing, .bottomLeading, .bottom,
      .bottomTrailing,
    ]
    for (index, alignment) in alignments.enumerated() {
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        for size in [CGSize(width: 32, height: 16), CGSize(width: 120, height: 80)] {
          let actual = try overlayView(
            alignment: UInt8(index), width: size.width, height: size.height)
          let expected = overlayBase.overlay(alignment: alignment) {
            Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: size.width, height: size.height)
          }
          let rendered = try raster(actual, direction)
          #expect(rendered.width == 116 && rendered.height == 76)
          #expect(rendered.matches(try raster(expected, direction)))
        }
      }
    }
  }

  @Test func signedInsetsAndStretchingReplacePositionedAnchors() throws {
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      for inset in [-8.0, 0, 8] {
        let operations =
          overlayBaseOperations + [
            TreeFixture.spacer(5, minimum: 0),
            TreeFixture.background(6, color: 0xff00_00ff, radius: 0),
            TreeFixture.children(6, [5]),
            TreeFixture.layoutFrame(
              7, minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity),
            TreeFixture.children(7, [6]),
            TreeFixture.padding(8, leading: inset, top: 4, trailing: 12, bottom: 6),
            TreeFixture.children(8, [7]), TreeFixture.overlay(1, alignment: 0),
            TreeFixture.children(1, [4, 8]),
          ]
        let view = try overlayModel(operations)
        let expected = overlayBase.overlay(alignment: .topLeading) {
          Color(.sRGB, red: 0, green: 0, blue: 1)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .padding(EdgeInsets(top: 4, leading: inset, bottom: 6, trailing: 12))
        }
        #expect(
          try raster(NativeNodeView(node: try #require(view.root), activate: { _ in }), direction)
            .matches(raster(expected, direction)))
      }
    }
  }

  @Test func emptyBaseAndEmptyOverlayFollowNativeComposition() throws {
    for emptyBase in [false, true] {
      let model = try overlayModel([
        TreeFixture.create(2, kind: NodeKindId.empty), TreeFixture.symbol(3),
        TreeFixture.overlay(1), TreeFixture.children(1, emptyBase ? [2, 3] : [3, 2]),
      ])
      let symbol = Image(systemName: "star").font(.system(size: 40)).symbolRenderingMode(
        .monochrome
      )
      .foregroundStyle(Color(.sRGB, red: 1, green: 0, blue: 0))
      // Select the expression outside ViewBuilder. ConditionalContent changes
      // empty-base layout and would hide the overlay in the reference itself.
      let expected =
        emptyBase
        ? AnyView(EmptyView().overlay { symbol })
        : AnyView(symbol.overlay { EmptyView() })
      #expect(
        try raster(NativeNodeView(node: try #require(model.root), activate: { _ in })).matches(
          raster(expected)))
    }
  }

  @Test func invalidOverlayTransactionsCannotPublishAndRemovedParentDataIsRejected() throws {
    let initial =
      overlayBaseOperations + [
        TreeFixture.symbol(5), TreeFixture.overlay(1), TreeFixture.children(1, [4, 5]),
        TreeFixture.root(1),
      ]
    let before = try NodeStore().staging(TreeFixture.frame(initial)).tree
    let snapshot = before
    let update = TreeFixture.overlay(1, alignment: 8, update: true)
    var invalid = [
      TreeFixture.overlay(1, alignment: 9, update: true), TreeFixture.children(1, []),
      TreeFixture.children(1, [4]),
      TreeFixture.children(1, [4, 5, 5]),
    ]
    for count in 0..<update.body.count {
      invalid.append(WireOperation(opcode: update.opcode, body: update.body.prefix(count)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try before.staging(
          TreeFixture.frame(
            [TreeFixture.symbol(5, name: "star.fill", update: true), operation], base: 1,
            revision: 2))
      }
      #expect(before == snapshot)
    }
    // The create payload ends after event bindings, with no parent-data tag.
    let create = TreeFixture.operation(OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(NodeKindId.empty))
      $0.integer(UInt16(0))
    }
    _ = try NodeStore().staging(TreeFixture.frame([create, TreeFixture.root(1)]))
    var obsolete = create.body
    obsolete.append(0)
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame([
          WireOperation(opcode: create.opcode, body: obsolete), TreeFixture.root(1),
        ]))
    }
  }
}

private var overlayBaseOperations: [WireOperation] {
  [
    TreeFixture.spacer(2, minimum: 0), TreeFixture.layoutFrame(3, width: 100, height: 60),
    TreeFixture.children(3, [2]), TreeFixture.background(4, color: 0xffff_0000, radius: 0),
    TreeFixture.children(4, [3]),
  ]
}

@MainActor private var overlayBase: some View {
  Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 100, height: 60)
}

@MainActor private func overlayModel(_ operations: [WireOperation]) throws -> RenderTree {
  let model = RenderTree()
  model.commit(try NodeStore().staging(TreeFixture.frame(operations + [TreeFixture.root(1)])).tree)
  return model
}

@MainActor private func overlayView(alignment: UInt8, width: Double, height: Double) throws
  -> some View
{
  let model = try overlayModel(
    overlayBaseOperations + [
      TreeFixture.spacer(5, minimum: 0), TreeFixture.layoutFrame(6, width: width, height: height),
      TreeFixture.children(6, [5]),
      TreeFixture.background(7, color: 0xff00_00ff, radius: 0), TreeFixture.children(7, [6]),
      TreeFixture.overlay(1, alignment: alignment), TreeFixture.children(1, [4, 7]),
    ])
  return NativeNodeView(node: try #require(model.root), activate: { _ in })
}

extension NativeRuntimeTests {
  @Test @MainActor func actualOverlayAlignmentAndSignedInsetsUpdateWithoutRemounting() async throws
  {
    let runtime = try await NativeRuntime.open(entrypoint: "overlays")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let before = try FrameState().staging(WireFrame.decode(output.bytes))
      let model = RenderTree()
      model.commit(before.tree)
      let button = try #require(model.root)
      let overlay = try #require(button.children.first)
      let nodes = model.nodes
      #expect(
        try raster(NativeNodeView(node: overlay, activate: { _ in })).matches(
          raster(overlayReference(updated: false))))
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      let press = NativeEvent(
        sequence: 1, displayedRevision: before.tree.revision, nodeID: button.id.node,
        handlerID: try #require(button.bindings[EventTagId.press]))
      let update = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: before.tree.epoch, events: [press]))
      model.commit(try before.staging(WireFrame.decode(update.bytes)).tree)
      for (id, node) in nodes { #expect(model.nodes[id] === node) }
      #expect(
        try raster(NativeNodeView(node: overlay, activate: { _ in })).matches(
          raster(overlayReference(updated: true))))
      try await runtime.acknowledge(update, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test @MainActor func actualGalleryOverlayCompositionsRenderInBothDirections() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "gallery-overlays")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      #expect(state.tree.nodes.values.contains { $0.kind == NodeKindId.overlay })
      let model = RenderTree()
      model.commit(state.tree)
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        let rendered = try raster(
          NativeNodeView(node: try #require(model.root), activate: { _ in })
            .padding(24).frame(width: 360).environment(\.colorScheme, .light), direction)
        #expect(rendered.width == 376 && rendered.height > 200)
        if let directory = ProcessInfo.processInfo.environment["BONSAI_RENDER_ARTIFACT_DIRECTORY"] {
          let url = URL(fileURLWithPath: directory, isDirectory: true)
          try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
          try rendered.write(
            to: url.appendingPathComponent(
              "gallery-overlays-\(direction == .leftToRight ? "ltr" : "rtl").png"))
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

@MainActor private func overlayReference(updated: Bool) -> some View {
  overlayBase.overlay(alignment: updated ? .bottomTrailing : .topLeading) {
    Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 32, height: 16)
      .padding(
        EdgeInsets(
          top: updated ? -2 : 2, leading: updated ? -4 : 4, bottom: updated ? -2 : 2,
          trailing: updated ? -4 : 4))
  }
}
