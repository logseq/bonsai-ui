import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func flow(
    _ id: UInt64, spacing: Double = 10, lineSpacing: Double = 7,
    alignment: UInt8 = 0, update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: 56, mask: 7, update: update) {
      $0.integer(spacing.bitPattern)
      $0.integer(lineSpacing.bitPattern)
      $0.integer(alignment)
    }
  }
}

@MainActor struct FlowLayoutTests {
  @Test func wrappingBoundariesAlignmentAndDirectionMatchExplicitNativeRows() throws {
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      for alignment in 0...2 {
        for (width, rows) in [
          (140.0, [[0, 1, 2]]), (90.0, [[0, 1], [2]]), (89.0, [[0], [1], [2]]),
        ] {
          let model = try blocks(alignment: UInt8(alignment))
          let actual = NativeNodeView(node: try #require(model.root), activate: { _ in })
            .frame(width: width)
          let expected = reference(rows, alignment: alignment).frame(
            width: width, alignment: anchor(alignment))
          #expect(
            try raster(actual, direction).matches(raster(expected, direction)),
            "width=\(width), alignment=\(alignment), direction=\(direction)")
        }
      }
    }
  }

  @Test func unboundedEmptyZeroWidthAndOversizedItemsRemainFinite() throws {
    let model = try blocks()
    #expect(
      try raster(NativeNodeView(node: #require(model.root), activate: { _ in }).fixedSize())
        .matches(raster(reference([[0, 1, 2]], alignment: 0))))
    for width in [0.0, 20.0] {
      let actual = NativeNodeView(node: try #require(model.root), activate: { _ in })
        .frame(width: width, alignment: .leading)
      let expected = reference([[0], [1], [2]], alignment: 0).frame(
        width: width, alignment: .leading)
      #expect(try raster(actual).matches(raster(expected)))
    }
    let empty = RenderTree()
    empty.commit(
      try NodeStore().staging(TreeFixture.frame([TreeFixture.flow(1), TreeFixture.root(1)])).tree)
    let rendered = try raster(NativeNodeView(node: #require(empty.root), activate: { _ in }))
    #expect(rendered.width == 16 && rendered.height == 16)
  }

  @Test func textCanWrapWithinOneItemAndUpdatesKeepKeyedChildren() throws {
    let model = RenderTree()
    let original = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.flow(1), TreeFixture.text(2, "A long label that needs more than one line"),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    model.commit(original)
    let text = try #require(model.nodes[2])
    let actual = NativeNodeView(node: try #require(model.root), activate: { _ in }).frame(
      width: 100)
    let expected = NativeNodeView(node: text, activate: { _ in }).frame(
      width: 100, alignment: .leading)
    #expect(try raster(actual).matches(raster(expected)))
    model.commit(
      try original.staging(
        TreeFixture.frame(
          [
            TreeFixture.flow(1, spacing: 0, lineSpacing: 0, alignment: 2, update: true)
          ], base: 1, revision: 2)
      ).tree)
    #expect(model.nodes[2] === text)
  }

  @Test func malformedFlowUpdatesCannotPublishPartialState() throws {
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.flow(1), TreeFixture.text(2, "Original"), TreeFixture.children(1, [2]),
        TreeFixture.root(1),
      ])
    ).tree
    var invalid = [TreeFixture.flow(1, alignment: 3, update: true)]
    for value in [-1.0, Double.nan, .infinity, -.infinity] {
      invalid.append(TreeFixture.flow(1, spacing: value, update: true))
      invalid.append(TreeFixture.flow(1, lineSpacing: value, update: true))
    }
    let update = TreeFixture.flow(1, update: true)
    for count in 0..<update.body.count {
      invalid.append(WireOperation(opcode: update.opcode, body: update.body.prefix(count)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try initial.staging(
          TreeFixture.frame(
            [
              TreeFixture.text(2, "Must not leak", update: true), operation,
            ], base: 1, revision: 2))
      }
      #expect(initial.revision == 1)
    }
  }

  private func blocks(alignment: UInt8 = 0) throws -> RenderTree {
    var operations = [TreeFixture.flow(1, alignment: alignment)]
    for index in 0..<3 {
      let id = UInt64(2 + index * 3)
      operations += [
        TreeFixture.spacer(id, minimum: 0),
        TreeFixture.layoutFrame(id + 1, width: 40, height: heights[index]),
        TreeFixture.children(id + 1, [id]),
        TreeFixture.background(id + 2, color: colors[index], radius: 0),
        TreeFixture.children(id + 2, [id + 1]),
      ]
    }
    operations += [TreeFixture.children(1, [4, 7, 10]), TreeFixture.root(1)]
    let model = RenderTree()
    model.commit(try NodeStore().staging(TreeFixture.frame(operations)).tree)
    return model
  }

  private let heights: [Double] = [20, 30, 15]
  private let colors: [UInt32] = [0xffff_0000, 0xff00_ff00, 0xff00_00ff]
  private func anchor(_ alignment: Int) -> Alignment { [.leading, .center, .trailing][alignment] }
  private func reference(_ rows: [[Int]], alignment: Int) -> some View {
    VStack(alignment: [.leading, .center, .trailing][alignment], spacing: 7) {
      ForEach(rows.indices, id: \.self) { row in
        HStack(alignment: .top, spacing: 10) {
          ForEach(rows[row], id: \.self) { index in
            Spacer(minLength: 0).frame(width: 40, height: heights[index])
              .background(
                [
                  Color(.sRGB, red: 1, green: 0, blue: 0), Color(.sRGB, red: 0, green: 1, blue: 0),
                  Color(.sRGB, red: 0, green: 0, blue: 1),
                ][index], in: RoundedRectangle(cornerRadius: 0, style: .continuous))
          }
        }
      }
    }
  }
}
