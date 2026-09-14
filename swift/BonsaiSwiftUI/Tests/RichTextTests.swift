import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

struct SpanFixture {
  var value: String
  var size: Double? = nil
  var weight: UInt8? = nil
  var color: UInt32? = nil
  var italic: UInt8 = 0
  var underline: UInt8 = 0
  var strike: UInt8 = 0
}

extension TreeFixture {
  static func richText(_ id: UInt64 = 1, spans: [SpanFixture], update: Bool = false)
    -> WireOperation
  {
    modifier(id, kind: NodeKindId.richText, mask: 1, update: update) {
      $0.integer(UInt16(spans.count))
      for span in spans {
        $0.integer(UInt32(span.value.utf8.count))
        $0.bytes.append(contentsOf: span.value.utf8)
        $0.integer(UInt8(span.size == nil ? 0 : 1))
        if let size = span.size { $0.integer(size.bitPattern) }
        $0.integer(UInt8(span.weight == nil ? 0 : 1))
        if let weight = span.weight { $0.integer(weight) }
        $0.integer(UInt8(span.color == nil ? 0 : 1))
        if let color = span.color { $0.integer(color) }
        $0.integer(span.italic)
        $0.integer(span.underline)
        $0.integer(span.strike)
      }
    }
  }
}

@MainActor struct RichTextTests {
  @Test func styledUnicodeRunsMatchNativeAttributedTextAndWrapAsOneParagraph() throws {
    let spans = [
      SpanFixture(value: "Hello "),
      SpanFixture(value: "世界 👩🏽‍💻", size: 22, weight: 2, color: 0xff00_00ff, italic: 1, underline: 1),
      SpanFixture(value: "\nAn obsolete claim", strike: 1),
    ]
    var expected = AttributedString("Hello ")
    var emphasis = AttributedString("世界 👩🏽‍💻")
    emphasis.font = .system(size: 22, weight: .semibold).italic()
    emphasis.foregroundColor = Color(.sRGB, red: 0, green: 0, blue: 1)
    emphasis.underlineStyle = .single
    var ending = AttributedString("\nAn obsolete claim")
    ending.strikethroughStyle = .single
    expected += emphasis
    expected += ending
    let model = try richModel(spans)
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      for width in [90.0, 240] {
        let actual = NativeNodeView(node: try #require(model.root), activate: { _ in }).font(
          .system(size: 18)
        ).foregroundStyle(Color.orange).frame(width: width)
        let reference = Text(expected).font(.system(size: 18)).foregroundStyle(Color.orange).frame(
          width: width)
        #expect(try raster(actual, direction).matches(raster(reference, direction)))
      }
    }
  }

  @Test func omittedAttributesInheritAndEmptySpansPreserveNativeTextSemantics() throws {
    for spans in [
      [], [SpanFixture(value: "")],
      [SpanFixture(value: "Read "), SpanFixture(value: "this", weight: 3, italic: 1)],
    ] {
      let model = try richModel(spans)
      var expected = AttributedString(spans.isEmpty ? "" : spans[0].value)
      if spans.count == 2 {
        var emphasis = AttributedString("this")
        emphasis.font = .title.bold().italic()
        expected += emphasis
      }
      let actual = NativeNodeView(node: try #require(model.root), activate: { _ in }).font(.title)
        .foregroundStyle(Color.orange)
      #expect(
        try raster(actual).matches(
          raster(Text(expected).font(.title).foregroundStyle(Color.orange))))
    }
  }

  @Test func malformedRunsAndRemovedStringOnlyPayloadRejectAtomically() throws {
    let initial = [
      TreeFixture.create(1), TreeFixture.text(2, "Original"),
      TreeFixture.richText(3, spans: [SpanFixture(value: "Valid")]),
      TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
    ]
    let before = try NodeStore().staging(TreeFixture.frame(initial)).tree
    var invalid = [
      TreeFixture.richText(3, spans: [SpanFixture(value: "x", weight: 4)], update: true),
      TreeFixture.richText(3, spans: [SpanFixture(value: "x", italic: 2)], update: true),
      TreeFixture.richText(3, spans: [SpanFixture(value: "x", underline: 2)], update: true),
      TreeFixture.richText(3, spans: [SpanFixture(value: "x", strike: 2)], update: true),
      TreeFixture.children(3, [2]),
    ]
    for size in [0, -1, Double.nan, .infinity, -.infinity] {
      invalid.append(
        TreeFixture.richText(3, spans: [SpanFixture(value: "x", size: size)], update: true))
    }
    let valid = TreeFixture.richText(3, spans: [SpanFixture(value: "New")], update: true)
    for count in 0..<valid.body.count {
      invalid.append(WireOperation(opcode: valid.opcode, body: valid.body.prefix(count)))
    }
    #expect(throws: (any Error).self) {
      try before.staging(
        TreeFixture.frame(
          [
            TreeFixture.text(4, "Unexpected child"), TreeFixture.children(3, [4]),
          ], base: 1, revision: 2))
    }
    var invalidUTF8 = valid.body
    invalidUTF8[24] = 0xff
    invalid.append(WireOperation(opcode: valid.opcode, body: invalidUTF8))
    let snapshot = before
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try before.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Must not leak", update: true), operation], base: 1, revision: 2))
      }
      #expect(before == snapshot)
    }
    let obsolete = TreeFixture.modifier(1, kind: NodeKindId.richText, mask: 1) {
      $0.integer(UInt16(1))
      $0.integer(UInt32(1))
      $0.integer(UInt8(120))
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(TreeFixture.frame([obsolete, TreeFixture.root(1)]))
    }
  }
}

@MainActor private func richModel(_ spans: [SpanFixture]) throws -> RenderTree {
  let model = RenderTree()
  model.commit(
    try NodeStore().staging(
      TreeFixture.frame([TreeFixture.richText(spans: spans), TreeFixture.root(1)])
    ).tree)
  return model
}

extension NativeRuntimeTests {
  @Test @MainActor func actualOcamlRichTextUpdatesRetainIdentity() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "rich-text")
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
        var expected = AttributedString(updated ? "Unread: " : "Read: ")
        var suffix = AttributedString(updated ? "世界 👩🏽‍💻" : "Hello")
        suffix.font = .system(size: updated ? 24 : 18, weight: updated ? .bold : .medium)
        suffix.foregroundColor = Color(.sRGB, red: updated ? 0 : 1, green: 0, blue: updated ? 1 : 0)
        if updated { suffix.underlineStyle = .single }
        expected += suffix
        #expect(
          try raster(NativeNodeView(node: label, activate: { _ in })).matches(
            raster(Text(expected))))
        for (id, node) in nodes { #expect(model.nodes[id] === node) }
      }
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test @MainActor func actualGalleryRichTextRendersStyledRuns() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "gallery-rich-text")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      let model = RenderTree()
      model.commit(state.tree)
      #expect(state.tree.nodes.values.contains { $0.kind == NodeKindId.richText })
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        // Keep multiline samples unconstrained vertically during final placement.
        let result = try raster(
          NativeNodeView(node: try #require(model.root), activate: { _ in }).padding(24).frame(
            width: 360
          ).fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, .light), direction)
        #expect(result.width == 376 && result.height > 180)
        if let path = ProcessInfo.processInfo.environment["BONSAI_RENDER_ARTIFACT_DIRECTORY"] {
          try result.write(
            to: URL(fileURLWithPath: path).appendingPathComponent(
              "gallery-rich-text-\(direction == .leftToRight ? "ltr" : "rtl").png"))
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
