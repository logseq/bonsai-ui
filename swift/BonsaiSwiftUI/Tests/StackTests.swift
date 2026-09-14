import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func nativeStack(
    _ id: UInt64, kind: Int, spacing: Double? = nil, alignment: UInt8 = 1, update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: kind, mask: kind == NodeKindId.stack ? 1 : 3, update: update) {
      if kind != NodeKindId.stack {
        $0.integer(UInt8(spacing == nil ? 0 : 1))
        if let spacing { $0.integer(spacing.bitPattern) }
      }
      $0.integer(alignment)
    }
  }

  static func layoutPriority(_ id: UInt64, _ value: Double, update: Bool = false) -> WireOperation {
    modifier(id, kind: NodeKindId.layoutPriority, mask: 1, update: update) {
      $0.integer(value.bitPattern)
    }
  }

  static func offset(_ id: UInt64, x: Double = 0, y: Double = 0, update: Bool = false)
    -> WireOperation
  {
    modifier(id, kind: NodeKindId.offset, mask: 3, update: update) {
      $0.integer(x.bitPattern)
      $0.integer(y.bitPattern)
    }
  }
}

@MainActor struct StackTests {
  @Test func stackAlignmentsAndSpacingMatchNativeLayoutInBothDirections() throws {
    let vertical: [VerticalAlignment] = [
      .top, .center, .bottom, .firstTextBaseline, .lastTextBaseline,
    ]
    let horizontal: [HorizontalAlignment] = [.leading, .center, .trailing]
    let overlay: [Alignment] = [
      .topLeading, .top, .topTrailing, .leading, .center, .trailing, .bottomLeading, .bottom,
      .bottomTrailing,
    ]
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      for spacing: Double? in [nil, -4, 0, 12] {
        for (index, alignment) in vertical.enumerated() {
          let actual = try stackView(
            kind: NodeKindId.row, spacing: spacing, alignment: UInt8(index))
          let expected = HStack(alignment: alignment, spacing: spacing.map { CGFloat($0) }) {
            stackText
            stackSymbol
          }
          #expect(try raster(actual, direction).matches(raster(expected, direction)))
        }
        for (index, alignment) in horizontal.enumerated() {
          let actual = try stackView(
            kind: NodeKindId.column, spacing: spacing, alignment: UInt8(index))
          let expected = VStack(alignment: alignment, spacing: spacing.map { CGFloat($0) }) {
            stackText
            stackSymbol
          }
          #expect(try raster(actual, direction).matches(raster(expected, direction)))
        }
      }
      for (index, alignment) in overlay.enumerated() {
        let actual = try stackView(kind: NodeKindId.stack, alignment: UInt8(index))
        let expected = ZStack(alignment: alignment) {
          stackText
          stackSymbol
        }
        #expect(try raster(actual, direction).matches(raster(expected, direction)))
      }
    }
  }

  @Test func layoutPriorityControlsCompressionAndOffsetPreservesMeasurement() throws {
    for priority in [-1.0, 0, 1, 10] {
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        let tree = try stackModel([
          TreeFixture.nativeStack(1, kind: NodeKindId.row, spacing: 4),
          TreeFixture.text(2, "Primary content"), TreeFixture.text(3, "Secondary content"),
          TreeFixture.layoutPriority(4, priority), TreeFixture.children(4, [2]),
          TreeFixture.offset(5, x: -7, y: 9), TreeFixture.children(5, [3]),
          TreeFixture.children(1, [4, 5]),
        ])
        let actual = NativeNodeView(node: try #require(tree.root), activate: { _ in }).frame(
          width: 150, height: 60)
        let expected = HStack(spacing: 4) {
          Text("Primary content").clipped().layoutPriority(priority)
          Text("Secondary content").clipped().offset(x: -7, y: 9)
        }.frame(width: 150, height: 60)
        #expect(try raster(actual, direction).matches(raster(expected, direction)))
      }
    }
  }

  @Test func malformedLayoutUpdatesCannotPublishPartialChanges() throws {
    let operations = [
      TreeFixture.nativeStack(1, kind: NodeKindId.row), TreeFixture.text(2, "Original"),
      TreeFixture.layoutPriority(3, 1), TreeFixture.children(3, [2]),
      TreeFixture.offset(4), TreeFixture.children(4, [3]),
      TreeFixture.nativeStack(5, kind: NodeKindId.column), TreeFixture.children(5, [4]),
      TreeFixture.nativeStack(6, kind: NodeKindId.stack, alignment: 4),
      TreeFixture.children(6, [5]),
      TreeFixture.children(1, [6]), TreeFixture.root(1),
    ]
    let before = try NodeStore().staging(TreeFixture.frame(operations)).tree
    let snapshot = before
    var invalid = [
      TreeFixture.nativeStack(1, kind: NodeKindId.row, alignment: 5, update: true),
      TreeFixture.nativeStack(5, kind: NodeKindId.column, alignment: 3, update: true),
      TreeFixture.nativeStack(6, kind: NodeKindId.stack, alignment: 9, update: true),
      TreeFixture.children(3, []), TreeFixture.children(4, []),
    ]
    for value in [Double.nan, .infinity, -.infinity] {
      invalid += [
        TreeFixture.nativeStack(1, kind: NodeKindId.row, spacing: value, update: true),
        TreeFixture.nativeStack(5, kind: NodeKindId.column, spacing: value, update: true),
        TreeFixture.layoutPriority(3, value, update: true),
        TreeFixture.offset(4, x: value, update: true),
        TreeFixture.offset(4, y: value, update: true),
      ]
    }
    for operation in [
      TreeFixture.nativeStack(1, kind: NodeKindId.row, spacing: 4, update: true),
      TreeFixture.nativeStack(5, kind: NodeKindId.column, spacing: 8, update: true),
      TreeFixture.nativeStack(6, kind: NodeKindId.stack, update: true),
      TreeFixture.layoutPriority(3, 2, update: true), TreeFixture.offset(4, update: true),
    ] {
      for length in 0..<operation.body.count {
        invalid.append(WireOperation(opcode: operation.opcode, body: operation.body.prefix(length)))
      }
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try before.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Must not leak", update: true), operation], base: 1, revision: 2))
      }
      #expect(before == snapshot)
    }
  }
}

@MainActor private var stackText: some View { Text("Two\nlines").clipped() }
@MainActor private var stackSymbol: some View {
  Image(systemName: "star.fill").font(.system(size: 30)).symbolRenderingMode(.monochrome)
    .foregroundStyle(Color(.sRGB, red: 1, green: 0, blue: 0))
}

@MainActor private func stackModel(_ operations: [WireOperation]) throws -> RenderTree {
  let model = RenderTree()
  model.commit(try NodeStore().staging(TreeFixture.frame(operations + [TreeFixture.root(1)])).tree)
  return model
}

@MainActor private func stackView(kind: Int, spacing: Double? = nil, alignment: UInt8) throws
  -> some View
{
  let model = try stackModel([
    TreeFixture.nativeStack(1, kind: kind, spacing: spacing, alignment: alignment),
    TreeFixture.text(2, "Two\nlines"), TreeFixture.symbol(3, name: "star.fill", size: 30),
    TreeFixture.children(1, [2, 3]),
  ])
  return NativeNodeView(node: try #require(model.root), activate: { _ in })
}

extension NativeRuntimeTests {
  @Test @MainActor func actualOcamlStackUpdatesPreserveIdentityAndNativeLayout() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "stacks")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let before = try FrameState().staging(WireFrame.decode(initial.bytes))
      let model = RenderTree()
      model.commit(before.tree)
      let button = try #require(model.root)
      let container = try #require(button.children.first)
      let nodes = model.nodes
      let first = try raster(NativeNodeView(node: container, activate: { _ in }))
      #expect(first.matches(try raster(stackReference(updated: false))))
      let handler = try #require(button.bindings[EventTagId.press])
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      let press = NativeEvent(
        sequence: 1, displayedRevision: before.tree.revision, nodeID: button.id.node,
        handlerID: handler)
      let updated = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: before.tree.epoch, events: [press]))
      model.commit(try before.staging(WireFrame.decode(updated.bytes)).tree)
      for (id, previous) in nodes { #expect(model.nodes[id] === previous) }
      let second = try raster(NativeNodeView(node: container, activate: { _ in }))
      #expect(second.matches(try raster(stackReference(updated: true))))
      #expect(first.pixels != second.pixels)
      try await runtime.acknowledge(updated, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test @MainActor func actualGalleryStacksRenderThroughNativeRuntime() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "gallery-stacks")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      let kinds = Set(state.tree.nodes.values.map(\.kind))
      #expect(
        kinds.isSuperset(of: [
          NodeKindId.row, NodeKindId.column, NodeKindId.stack, NodeKindId.layoutPriority,
          NodeKindId.offset,
        ]))
      let model = RenderTree()
      model.commit(state.tree)
      let root = try #require(model.root)
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        let rendered = try raster(
          NativeNodeView(node: root, activate: { _ in })
            .padding(24).frame(width: 360).environment(\.colorScheme, .light), direction)
        #expect(rendered.width == 376 && rendered.height > 200)
        if let directory = ProcessInfo.processInfo.environment["BONSAI_RENDER_ARTIFACT_DIRECTORY"] {
          let url = URL(fileURLWithPath: directory, isDirectory: true)
          try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
          try rendered.write(
            to: url.appendingPathComponent(
              "gallery-stacks-\(direction == .leftToRight ? "ltr" : "rtl").png"))
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

@MainActor private func stackReference(updated: Bool) -> some View {
  VStack(alignment: updated ? .trailing : .leading, spacing: updated ? 16 : 4) {
    HStack(alignment: updated ? .lastTextBaseline : .top, spacing: updated ? 20 : 4) {
      Text("Primary content").clipped().layoutPriority(updated ? 1 : 0)
      Text("Secondary content").clipped().offset(x: updated ? -7 : 0, y: updated ? 9 : 0)
    }.frame(width: 150, height: 60)
    ZStack(alignment: updated ? .bottomTrailing : .topLeading) {
      Text("Two\nlines").clipped()
      stackSymbol
    }
  }
}
