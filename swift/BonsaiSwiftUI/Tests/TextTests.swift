import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func nativeText(
    _ id: UInt64 = 1, value: String = "First line\n世界 👩🏽‍💻\nFinal line", size: Double? = nil,
    weight: UInt8? = nil, spacing: Double? = nil, color: UInt32? = nil,
    alignment: UInt8 = 0, lineLimit: UInt32? = nil, truncation: UInt8 = 0, update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: NodeKindId.text, mask: 31, update: update) {
      $0.integer(UInt32(value.utf8.count))
      $0.bytes.append(contentsOf: value.utf8)
      $0.integer(UInt8(1))
      $0.integer(UInt8(size == nil ? 0 : 1))
      if let size { $0.integer(size.bitPattern) }
      $0.integer(UInt8(weight == nil ? 0 : 1))
      if let weight { $0.integer(weight) }
      $0.integer(UInt8(spacing == nil ? 0 : 1))
      if let spacing { $0.integer(spacing.bitPattern) }
      $0.integer(UInt8(color == nil ? 0 : 1))
      if let color { $0.integer(color) }
      $0.bytes.append(contentsOf: [0, 0, 0])  // Body role, inherited foreground, no italic.
      $0.integer(alignment)
      $0.integer(UInt8(lineLimit == nil ? 0 : 1))
      if let lineLimit { $0.integer(lineLimit) }
      $0.integer(truncation)
    }
  }
}

@MainActor struct TextTests {
  @Test func nativeTruncationAndLineLimitsMatchInBothDirections() throws {
    let value = "First: a longer subject\nSecond: 世界 👩🏽‍💻\nLast: another longer line"
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      for (index, mode) in [Text.TruncationMode.tail, .head, .middle].enumerated() {
        for lineLimit: UInt32? in [nil, 1, 2] {
          let actual = try textView(
            TreeFixture.nativeText(value: value, lineLimit: lineLimit, truncation: UInt8(index)))
          let expected = Text(verbatim: value).font(.system(size: 17)).lineLimit(
            lineLimit.map(Int.init)
          ).truncationMode(
            mode)
          #expect(
            try raster(actual.frame(width: 120), direction).matches(
              raster(expected.frame(width: 120), direction)))
        }
      }
    }
  }

  @Test func lineSpacingUsesNativePointDistancesAndTextAlignment() throws {
    let value = "Short\nA wider middle line\n结束"
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      for (index, alignment) in [TextAlignment.leading, .center, .trailing].enumerated() {
        for spacing in [0.0, 4, 10] {
          let actual = try textView(
            TreeFixture.nativeText(
              value: value, size: 18, spacing: spacing, alignment: UInt8(index)))
          let expected = Text(verbatim: value).font(.system(size: 18)).multilineTextAlignment(
            alignment
          ).lineSpacing(spacing)
          #expect(try raster(actual, direction).matches(raster(expected, direction)))
        }
      }
    }
  }

  @Test func omittedAttributesInheritFontColorAndSpacing() throws {
    let value = "**Literal** content\nWith another line"
    for (index, weight) in [Font.Weight.regular, .medium, .semibold, .bold].enumerated() {
      let actual = try textView(TreeFixture.nativeText(value: value, weight: UInt8(index)))
      let expected = Text(verbatim: value).font(.title.weight(weight))
      #expect(
        try raster(actual.font(.title).foregroundStyle(Color.orange).lineSpacing(6))
          .matches(raster(expected.foregroundStyle(Color.orange).lineSpacing(6))))
    }
    let actual = try textView(TreeFixture.nativeText(value: value, size: 20, color: 0x8000_00ff))
      .environment(\.bonsaiFontFamily, "Georgia")
    let expected = Text(verbatim: value).font(.custom("Georgia", size: 20, relativeTo: .body))
      .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 128.0 / 255))
    #expect(try raster(actual).matches(raster(expected)))
  }

  @Test func invalidTextPropertiesRejectTheWholeTransaction() throws {
    let before = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.create(1), TreeFixture.text(2, "Original"), TreeFixture.nativeText(3),
        TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
      ])
    ).tree
    var invalid = [
      TreeFixture.nativeText(3, alignment: 3, update: true),
      TreeFixture.nativeText(3, lineLimit: 0, update: true),
      TreeFixture.nativeText(3, truncation: 3, update: true),
      TreeFixture.nativeText(3, weight: 4, update: true),
    ]
    for spacing in [-1, Double.nan, .infinity, -.infinity] {
      invalid.append(TreeFixture.nativeText(3, spacing: spacing, update: true))
    }
    for size in [0, -1, Double.nan, .infinity, -.infinity] {
      invalid.append(TreeFixture.nativeText(3, size: size, update: true))
    }
    let update = TreeFixture.nativeText(3, update: true)
    for count in 0..<update.body.count {
      invalid.append(WireOperation(opcode: update.opcode, body: update.body.prefix(count)))
    }
    let snapshot = before
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

@MainActor private func textView(_ operation: WireOperation) throws -> some View {
  let model = RenderTree()
  model.commit(try NodeStore().staging(TreeFixture.frame([operation, TreeFixture.root(1)])).tree)
  return NativeNodeView(node: try #require(model.root), activate: { _ in })
}

extension NativeRuntimeTests {
  @Test @MainActor func actualTextPropertiesUpdateWithoutRemounting() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "text-layout")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let before = try FrameState().staging(WireFrame.decode(output.bytes))
      let model = RenderTree()
      model.commit(before.tree)
      let button = try #require(model.root)
      let label = try #require(button.children.first)
      let nodes = model.nodes
      for updated in [false, true] {
        if updated {
          try await runtime.acknowledge(output, monotonicNanoseconds: 2)
          let event = NativeEvent(
            sequence: 1, displayedRevision: before.tree.revision, nodeID: button.id.node,
            handlerID: try #require(button.bindings[EventTagId.press]))
          let update = try await runtime.pump(
            monotonicNanoseconds: 3,
            events: EventBatch.encode(epoch: before.tree.epoch, events: [event]))
          model.commit(try before.staging(WireFrame.decode(update.bytes)).tree)
          try await runtime.acknowledge(update, monotonicNanoseconds: 4)
        }
        let reference = Text(
          verbatim: "First: a longer subject\nSecond: 世界 👩🏽‍💻\nLast: another longer line"
        )
        .font(.system(size: updated ? 20 : 16, weight: updated ? .bold : .medium))
        .foregroundStyle(Color(.sRGB, red: updated ? 0 : 1, green: 0, blue: updated ? 1 : 0))
        .multilineTextAlignment(updated ? .trailing : .leading).lineLimit(updated ? 2 : 3)
        .lineSpacing(updated ? 8 : 0).truncationMode(updated ? .middle : .tail).frame(width: 180)
        #expect(
          try raster(NativeNodeView(node: label, activate: { _ in })).matches(raster(reference)))
        for (id, node) in nodes { #expect(model.nodes[id] === node) }
      }
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test @MainActor func actualGalleryNativeTextRenders() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "gallery-text")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      let model = RenderTree()
      model.commit(state.tree)
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        let result = try raster(
          NativeNodeView(node: try #require(model.root), activate: { _ in }).padding(24).frame(
            width: 360
          )
          .fixedSize(horizontal: false, vertical: true).environment(\.colorScheme, .light),
          direction)
        #expect(result.width == 376 && result.height > 250)
        if let path = ProcessInfo.processInfo.environment["BONSAI_RENDER_ARTIFACT_DIRECTORY"] {
          try result.write(
            to: URL(fileURLWithPath: path).appendingPathComponent(
              "gallery-text-\(direction == .leftToRight ? "ltr" : "rtl").png"))
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

@MainActor private struct ScaledTextReference: View {
  @ScaledMetric(relativeTo: .body) private var size = 18.0
  var body: some View { Text("Adaptive text").font(.system(size: size)) }
}

extension TextTests {
  @Test @MainActor func explicitTextSizesFollowNativeDynamicType() throws {
    let actual = try textView(TreeFixture.nativeText(value: "Adaptive text", size: 18))
    for category in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
      #expect(
        try raster(actual.dynamicTypeSize(category)).matches(
          raster(ScaledTextReference().dynamicTypeSize(category))))
    }
  }
}
