import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func spacer(_ id: UInt64, minimum: Double? = nil) -> WireOperation {
    operation(OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(NodeKindId.spacer))
      $0.integer(UInt8(minimum == nil ? 0 : 1))
      if let minimum { $0.integer(minimum.bitPattern) }
      $0.integer(UInt16(0))
    }
  }

  static func layoutFrame(
    _ id: UInt64 = 1, width: Double? = nil, height: Double? = nil,
    minWidth: Double? = nil, idealWidth: Double? = nil, maxWidth: Double? = nil,
    minHeight: Double? = nil, idealHeight: Double? = nil, maxHeight: Double? = nil,
    alignment: UInt8 = 4, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(NodeKindId.frame))
      if update { $0.integer(UInt64(511)) }
      func optional(_ writer: inout WireWriter, _ value: Double?) {
        writer.integer(UInt8(value == nil ? 0 : 1))
        if let value { writer.integer(value.bitPattern) }
      }
      func maximum(_ writer: inout WireWriter, _ value: Double?) {
        if value == .infinity { writer.integer(UInt8(2)) } else { optional(&writer, value) }
      }
      optional(&$0, width)
      optional(&$0, height)
      optional(&$0, minWidth)
      optional(&$0, idealWidth)
      maximum(&$0, maxWidth)
      optional(&$0, minHeight)
      optional(&$0, idealHeight)
      maximum(&$0, maxHeight)
      $0.integer(alignment)
      if !update {
        $0.integer(UInt16(0))
      }
    }
  }
}

@MainActor
struct FrameTests {
  @Test func nativeSpacerReservesGapsAndRejectsInvalidMinimums() throws {
    for minimum: Double? in [nil, 0, 24] {
      let model = RenderTree()
      model.commit(
        try NodeStore().staging(
          TreeFixture.frame([
            TreeFixture.create(1, kind: NodeKindId.row),
            TreeFixture.symbol(2, name: "star.fill", size: 18),
            TreeFixture.spacer(3, minimum: minimum),
            TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
          ])
        ).tree)
      let root = try #require(model.root)
      #expect(
        try raster(NativeNodeView(node: root, activate: { _ in }).frame(width: 140, height: 40))
          .matches(
            raster(
              HStack {
                referenceSymbol
                Spacer(minLength: minimum.map { CGFloat($0) })
              }
              .frame(width: 140, height: 40))))
    }
    for invalid in [-1, Double.nan, Double.infinity, -Double.infinity] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(
          TreeFixture.frame([TreeFixture.spacer(1, minimum: invalid), TreeFixture.root(1)]))
      }
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.spacer(1), TreeFixture.symbol(2), TreeFixture.children(1, [2]),
          TreeFixture.root(1),
        ]))
    }
  }

  @Test func fixedFramesMatchNativeAlignmentIncludingRightToLeftAndZeroSize() throws {
    let alignments: [Alignment] = [
      .topLeading, .top, .topTrailing, .leading, .center, .trailing,
      .bottomLeading, .bottom, .bottomTrailing,
    ]
    for (index, alignment) in alignments.enumerated() {
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        for width in [0.0, 100.0] {
          let actual = try frameView(
            TreeFixture.layoutFrame(
              width: width, height: 70, alignment: UInt8(index)))
          let expected = referenceSymbol.frame(width: width, height: 70, alignment: alignment)
          let actualImage = try raster(actual, direction)
          let expectedImage = try raster(expected, direction)
          let matches = actualImage.matches(expectedImage)
          #expect(matches, "Alignment \(index), direction \(direction), width \(width)")
        }
      }
    }
  }

  @Test func flexibleFramesUseNativeProposalsAndIdealDimensions() throws {
    let cases: [(WireOperation, AnyView)] = [
      (TreeFixture.layoutFrame(), AnyView(referenceSymbol)),
      (
        TreeFixture.layoutFrame(
          minWidth: 50, idealWidth: 70, maxWidth: 140,
          minHeight: 30, idealHeight: 45, maxHeight: 80),
        AnyView(
          referenceSymbol.frame(
            minWidth: 50, idealWidth: 70, maxWidth: 140,
            minHeight: 30, idealHeight: 45, maxHeight: 80))
      ),
      (
        TreeFixture.layoutFrame(maxWidth: .infinity, maxHeight: .infinity, alignment: 8),
        AnyView(
          referenceSymbol.frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: .bottomTrailing))
      ),
      (
        TreeFixture.layoutFrame(width: 90, minHeight: 30, maxHeight: .infinity, alignment: 0),
        AnyView(
          referenceSymbol.frame(width: 90, alignment: .topLeading)
            .frame(minHeight: 30, maxHeight: .infinity, alignment: .topLeading))
      ),
      (
        TreeFixture.layoutFrame(height: 60, minWidth: 50, maxWidth: 120, alignment: 2),
        AnyView(
          referenceSymbol.frame(height: 60, alignment: .topTrailing)
            .frame(minWidth: 50, maxWidth: 120, alignment: .topTrailing))
      ),
    ]
    for (operation, expected) in cases {
      let actual = try frameView(operation)
      #expect(try raster(actual).matches(raster(expected)))
      for size in [CGSize(width: 120, height: 90), CGSize(width: 280, height: 180)] {
        #expect(
          try raster(actual.frame(width: size.width, height: size.height))
            .matches(raster(expected.frame(width: size.width, height: size.height))))
      }
    }
  }

  @Test func invalidFramesCannotPublishPartialUpdates() throws {
    let initial = TreeFixture.frame([
      TreeFixture.layoutFrame(width: 100, height: 70), TreeFixture.symbol(2),
      TreeFixture.children(1, [2]), TreeFixture.root(1),
    ])
    let before = try NodeStore().staging(initial).tree
    let snapshot = before
    var corruptions = [
      TreeFixture.layoutFrame(width: 40, minWidth: 0, update: true),
      TreeFixture.layoutFrame(height: 40, idealHeight: 40, update: true),
      TreeFixture.layoutFrame(width: 40, maxWidth: .infinity, update: true),
      TreeFixture.layoutFrame(minWidth: 20, maxWidth: 10, update: true),
      TreeFixture.layoutFrame(minHeight: 20, idealHeight: 10, update: true),
      TreeFixture.layoutFrame(idealWidth: 20, maxWidth: 10, update: true),
      TreeFixture.layoutFrame(alignment: 9, update: true), TreeFixture.children(1, []),
    ]
    for invalid in [-1, Double.nan, -Double.infinity] {
      corruptions += [
        TreeFixture.layoutFrame(width: invalid, update: true),
        TreeFixture.layoutFrame(height: invalid, update: true),
        TreeFixture.layoutFrame(minWidth: invalid, update: true),
        TreeFixture.layoutFrame(idealHeight: invalid, update: true),
        TreeFixture.layoutFrame(maxWidth: invalid, update: true),
      ]
    }
    corruptions.append(TreeFixture.layoutFrame(width: .infinity, update: true))
    let operation = TreeFixture.layoutFrame(width: 100, height: 70, update: true)
    for count in 0..<operation.body.count {
      corruptions.append(
        WireOperation(opcode: operation.opcode, body: operation.body.prefix(count)))
    }
    for corruption in corruptions {
      #expect(throws: (any Error).self) {
        try before.staging(
          TreeFixture.frame(
            [
              TreeFixture.symbol(2, name: "star.fill", update: true), corruption,
            ], base: 1, revision: 2))
      }
      #expect(before == snapshot)
    }
  }
}

@MainActor private var referenceSymbol: some View {
  Image(systemName: "star.fill").font(.system(size: 18))
    .symbolRenderingMode(.monochrome).foregroundStyle(Color(.sRGB, red: 1, green: 0, blue: 0))
}

@MainActor private func frameView(_ operation: WireOperation) throws -> some View {
  let model = RenderTree()
  model.commit(
    try NodeStore().staging(
      TreeFixture.frame([
        operation, TreeFixture.symbol(2, name: "star.fill", size: 18),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree)
  return NativeNodeView(node: try #require(model.root), activate: { _ in })
}

extension NativeRuntimeTests {
  @Test @MainActor func actualOcamlSpacerPreservesFixedBlankSpace() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "spacers")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      let model = RenderTree()
      model.commit(state.tree)
      let root = try #require(model.root)
      let actual = try raster(NativeNodeView(node: root, activate: { _ in }))
      let expected = try raster(
        HStack {
          referenceSymbol
          Spacer(minLength: 0).frame(width: 100)
          referenceSymbol
        })
      #expect(actual.matches(expected))
      #expect(actual.width > 140)
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test @MainActor func actualGalleryFrameSectionRendersThroughNativeRuntime() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "gallery-frames")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      let frames = state.tree.nodes.values.compactMap { node -> RenderFrame? in
        if case .frame(let frame) = node.properties { return frame }
        return nil
      }
      #expect(frames.count == 11)
      #expect(Set(frames.map(\.alignment)) == Set(0...8))
      #expect(frames.contains { $0.maxWidth == .fill })
      #expect(frames.contains { $0.idealWidth == 140 })
      let model = RenderTree()
      model.commit(state.tree)
      let root = try #require(model.root)
      let rendered = try raster(
        NativeNodeView(node: root, activate: { _ in })
          .padding(24).frame(width: 360).environment(\.colorScheme, .light))
      if let directory = ProcessInfo.processInfo.environment["BONSAI_RENDER_ARTIFACT_DIRECTORY"] {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try rendered.write(to: url.appendingPathComponent("gallery-frames.png"))
      }
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test @MainActor func realFrameChangesBetweenFixedAndFlexibleWithoutRemounting() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "frames")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let before = try FrameState().staging(WireFrame.decode(output.bytes))
      let model = RenderTree()
      model.commit(before.tree)
      let frame = try #require(model.nodes.values.first { $0.kind == NodeKindId.frame })
      let symbol = try #require(model.nodes.values.first { $0.kind == NodeKindId.symbol })
      #expect(
        try raster(NativeNodeView(node: frame, activate: { _ in }))
          .matches(
            raster(referenceSymbol.frame(width: 100, height: 70, alignment: .topLeading))))
      let button = try #require(before.tree.nodes.values.first { $0.kind == NodeKindId.button })
      let handler = try #require(button.bindings[EventTagId.press])
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      let press = NativeEvent(
        sequence: 1, displayedRevision: before.tree.revision,
        nodeID: button.id, handlerID: handler)
      let updated = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: before.tree.epoch, events: [press]))
      let after = try before.staging(WireFrame.decode(updated.bytes))
      model.commit(after.tree)
      #expect(model.nodes[frame.id.node] === frame)
      #expect(model.nodes[symbol.id.node] === symbol)
      #expect(
        try raster(NativeNodeView(node: frame, activate: { _ in }).frame(width: 200, height: 140))
          .matches(
            raster(
              referenceSymbol.frame(
                minWidth: 0, maxWidth: .infinity,
                minHeight: 20, idealHeight: 50, maxHeight: 90, alignment: .bottomTrailing
              )
              .frame(width: 200, height: 140))))
      try await runtime.acknowledge(updated, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
