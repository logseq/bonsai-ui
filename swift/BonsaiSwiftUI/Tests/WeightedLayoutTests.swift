import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func weighted(
    _ id: UInt64, vertical: Bool = false, spacing: Double? = 0,
    alignment: UInt8 = 1, items: [(Double?, Bool)], update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: vertical ? 20 : 18, mask: 7, update: update) {
      $0.integer(UInt8(spacing == nil ? 0 : 1))
      if let spacing { $0.integer(spacing.bitPattern) }
      $0.integer(alignment)
      $0.integer(UInt32(items.count))
      for (weight, fills) in items {
        $0.integer(UInt8(weight == nil ? 0 : 1))
        if let weight {
          $0.integer(weight.bitPattern)
          $0.integer(UInt8(fills ? 1 : 0))
        }
      }
    }
  }
}

@MainActor struct WeightedLayoutTests {
  @Test func intrinsicChildrenUseNativeBaselinesAndCrossAlignment() throws {
    let verticalAlignments: [VerticalAlignment] = [
      .top, .center, .bottom, .firstTextBaseline, .lastTextBaseline,
    ]
    let horizontalAlignments: [HorizontalAlignment] = [.leading, .center, .trailing]
    for vertical in [false, true] {
      for alignment in 0..<(vertical ? 3 : 5) {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
          let model = RenderTree()
          model.commit(
            try NodeStore().staging(
              TreeFixture.frame([
                TreeFixture.weighted(
                  1, vertical: vertical, spacing: nil, alignment: UInt8(alignment),
                  items: [(nil, false), (nil, false)]),
                TreeFixture.text(2, "Two\nlines"),
                TreeFixture.symbol(3, name: "star.fill", size: 30),
                TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
              ])
            ).tree)
          let children = Group {
            Text("Two\nlines").font(.system(size: 17)).clipped()
            Image(systemName: "star.fill").font(.system(size: 30)).symbolRenderingMode(.monochrome)
              .foregroundStyle(Color(.sRGB, red: 1, green: 0, blue: 0))
          }
          let expected = Group {
            if vertical {
              VStack(alignment: horizontalAlignments[alignment], spacing: 16) { children }
            } else {
              HStack(alignment: verticalAlignments[alignment]) { children }
            }
          }
          #expect(
            try raster(
              NativeNodeView(node: try #require(model.root), activate: { _ in }), direction
            ).matches(raster(expected, direction)))
        }
      }
    }
  }

  @Test func proportionalSharesAndFixedContentHaveExactNativeGeometry() throws {
    for vertical in [false, true] {
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        let content = try weightedView(
          vertical: vertical, sizes: [40, nil, nil],
          items: [(nil, false), (1, true), (3, true)], spacing: 10)
        let actual =
          vertical
          ? AnyView(content.frame(width: 20, height: 300))
          : AnyView(content.frame(width: 300, height: 20))
        let expected = referenceBlocks(vertical: vertical, lengths: [40, 60, 180], spacing: 10)
        #expect(try raster(actual, direction).matches(raster(expected, direction)))
      }
    }
  }

  @Test func contentSizedSharesUnboundedProposalsAndExtremeWeightsStayFinite() throws {
    let cases: [(sizes: [Double?], items: [(Double?, Bool)], width: Double?, expected: [Double])] =
      [
        ([40, 20, 30], [(nil, false), (1, false), (2, false)], 300, [40, 20, 30]),
        ([40, 20, 30], [(nil, false), (1, true), (2, true)], nil, [40, 20, 30]),
        ([nil, nil, nil], [(1e308, true), (1e308, true), (1e308, true)], 300, [100, 100, 100]),
        ([40, nil, nil], [(nil, false), (1, true), (1, true)], 20, [40, 0, 0]),
      ]
    for test in cases {
      let content = try weightedView(sizes: test.sizes, items: test.items)
      // ImageRenderer reproposes its measured size. fixedSize keeps the
      // unspecified-width case unspecified through final placement.
      let actual = Group {
        if test.width == nil {
          content.fixedSize(horizontal: true, vertical: false).frame(height: 20)
        } else {
          content.frame(width: test.width.map { CGFloat($0) }, height: 20)
        }
      }
      let expected = referenceBlocks(vertical: false, lengths: test.expected, spacing: 0)
        .frame(width: test.width.map { CGFloat($0) }, height: 20)
      #expect(
        try raster(actual).matches(raster(expected)),
        "Sizes \(test.sizes); width \(String(describing: test.width))")
    }
  }

  @Test func emptyChildrenAndDefaultSpacingFollowNativeSubviewSemantics() throws {
    let model = RenderTree()
    model.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.weighted(1, items: [(1, true), (1, true)]),
          TreeFixture.create(2, kind: NodeKindId.empty),
          TreeFixture.spacer(3, minimum: 0),
          TreeFixture.background(4, color: 0xffff_0000, radius: 0),
          TreeFixture.layoutFrame(5, height: 20), TreeFixture.children(5, [3]),
          TreeFixture.children(4, [5]), TreeFixture.children(1, [2, 4]), TreeFixture.root(1),
        ])
      ).tree)
    #expect(
      try raster(
        NativeNodeView(node: try #require(model.root), activate: { _ in }).frame(
          width: 100, height: 20)
      )
      .matches(raster(Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 100, height: 20))))
    for vertical in [false, true] {
      let empty = try weightedView(vertical: vertical, sizes: [], items: [], spacing: nil)
      #expect(try raster(empty).width == 16)
      let content = try weightedView(
        vertical: vertical, sizes: [20, 40, 30], items: [(nil, false), (nil, false), (nil, false)],
        spacing: nil)
      #expect(
        try raster(content).matches(
          raster(
            referenceBlocks(
              vertical: vertical, lengths: [20, 40, 30], spacing: vertical ? 16 : nil))))
    }
  }

  @Test func invalidWeightedTransactionsCannotPublishPartialChanges() throws {
    let initial = [
      TreeFixture.weighted(1, items: [(1, true)]), TreeFixture.text(2, "Original"),
      TreeFixture.children(1, [2]), TreeFixture.root(1),
    ]
    let before = try NodeStore().staging(TreeFixture.frame(initial)).tree
    let snapshot = before
    var invalid = [
      TreeFixture.weighted(1, alignment: 5, items: [(1, true)], update: true),
      TreeFixture.weighted(1, items: [], update: true),
      TreeFixture.weighted(1, items: [(1, true), (2, true)], update: true),
    ]
    for weight in [0, -1, Double.nan, .infinity, -.infinity] {
      invalid.append(TreeFixture.weighted(1, items: [(weight, true)], update: true))
    }
    for spacing in [Double.nan, .infinity, -.infinity] {
      invalid.append(TreeFixture.weighted(1, spacing: spacing, items: [(1, true)], update: true))
    }
    let valid = TreeFixture.weighted(1, items: [(1, true)], update: true)
    for count in 0..<valid.body.count {
      invalid.append(WireOperation(opcode: valid.opcode, body: valid.body.prefix(count)))
    }
    var badFlag = valid.body
    badFlag[badFlag.count - 1] = 2
    invalid.append(WireOperation(opcode: valid.opcode, body: badFlag))
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

@MainActor private func weightedView(
  vertical: Bool = false, sizes: [Double?], items: [(Double?, Bool)], spacing: Double? = 0
) throws -> some View {
  var operations: [WireOperation] = [
    TreeFixture.weighted(1, vertical: vertical, spacing: spacing, items: items)
  ]
  let colors: [UInt32] = [0xffff_0000, 0xff00_ff00, 0xff00_00ff]
  var children: [UInt64] = []
  for (index, size) in sizes.enumerated() {
    let id = UInt64(2 + index * 3)
    operations += [
      TreeFixture.spacer(id, minimum: 0),
      TreeFixture.layoutFrame(id + 1, width: vertical ? 20 : size, height: vertical ? size : 20),
      TreeFixture.children(id + 1, [id]),
      TreeFixture.background(id + 2, color: colors[index], radius: 0),
      TreeFixture.children(id + 2, [id + 1]),
    ]
    children.append(id + 2)
  }
  operations += [TreeFixture.children(1, children), TreeFixture.root(1)]
  let model = RenderTree()
  model.commit(try NodeStore().staging(TreeFixture.frame(operations)).tree)
  return NativeNodeView(node: try #require(model.root), activate: { _ in })
}

@MainActor private func referenceBlocks(vertical: Bool, lengths: [Double], spacing: Double?)
  -> some View
{
  let colors = [
    Color(.sRGB, red: 1, green: 0, blue: 0), Color(.sRGB, red: 0, green: 1, blue: 0),
    Color(.sRGB, red: 0, green: 0, blue: 1),
  ]
  let children = ForEach(Array(lengths.enumerated()), id: \.offset) { index, length in
    Spacer(minLength: 0).frame(width: vertical ? 20 : length, height: vertical ? length : 20)
      .background(colors[index], in: RoundedRectangle(cornerRadius: 0, style: .continuous))
  }
  return Group {
    if vertical {
      VStack(spacing: spacing.map { CGFloat($0) }) { children }
    } else {
      HStack(spacing: spacing.map { CGFloat($0) }) { children }
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualWeightedUpdatesAndReordersRetainChildren() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "weights")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let before = try FrameState().staging(WireFrame.decode(output.bytes))
      let model = RenderTree()
      model.commit(before.tree)
      let button = try #require(model.root)
      let content = try #require(button.children.first)
      let nodes = model.nodes
      let initial = try raster(NativeNodeView(node: content, activate: { _ in }))
      #expect(
        initial.matches(
          try raster(
            HStack(spacing: 0) {
              Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 100, height: 20)
              Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 200, height: 20)
            })))
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      let press = NativeEvent(
        sequence: 1, displayedRevision: before.tree.revision,
        nodeID: button.id.node, handlerID: try #require(button.bindings[EventTagId.press]))
      let update = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: before.tree.epoch, events: [press]))
      model.commit(try before.staging(WireFrame.decode(update.bytes)).tree)
      for (id, node) in nodes { #expect(model.nodes[id] === node) }
      #expect(
        try raster(NativeNodeView(node: content, activate: { _ in })).matches(
          raster(
            HStack(spacing: 0) {
              Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 225, height: 20)
              Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 75, height: 20)
            })))
      try await runtime.acknowledge(update, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test @MainActor func actualGalleryWeightedLayoutsRenderInBothDirections() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "gallery-weights")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      #expect(Set(state.tree.nodes.values.map(\.kind)).isSuperset(of: [18, 20]))
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
              "gallery-weights-\(direction == .leftToRight ? "ltr" : "rtl").png"))
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
