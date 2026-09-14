import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func modifier(
    _ id: UInt64, kind: Int, mask: UInt64, update: Bool = false,
    _ props: (inout WireWriter) -> Void
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(kind))
      if update { $0.integer(mask) }
      props(&$0)
      if !update {
        $0.integer(UInt16(0))
      }
    }
  }

  static func padding(
    _ id: UInt64, leading: Double = 12, top: Double = 8,
    trailing: Double = 4, bottom: Double = 6, update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: NodeKindId.padding, mask: 1, update: update) {
      for value in [leading, top, trailing, bottom] { $0.integer(value.bitPattern) }
    }
  }

  static func background(
    _ id: UInt64, color: UInt32 = 0xff20_60a0, radius: Double = 8,
    update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: NodeKindId.background, mask: 3, update: update) {
      $0.integer(color)
      $0.integer(radius.bitPattern)
    }
  }

  static func clip(
    _ id: UInt64, radius: Double = 10, antialiased: UInt8 = 1,
    update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: NodeKindId.clip, mask: 3, update: update) {
      $0.integer(radius.bitPattern)
      $0.integer(antialiased)
    }
  }

  static func opacity(_ id: UInt64, _ value: Double, update: Bool = false) -> WireOperation {
    modifier(id, kind: NodeKindId.opacity, mask: 1, update: update) { $0.integer(value.bitPattern) }
  }
}

@MainActor
struct ModifierTests {
  @Test func framedSpacerPreservesNativeBackgroundExpansion() throws {
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.spacer(1, minimum: 0),
          TreeFixture.background(2, color: 0xff00_00ff, radius: 0),
          TreeFixture.layoutFrame(3, maxWidth: .infinity, maxHeight: .infinity),
          TreeFixture.children(2, [1]), TreeFixture.children(3, [2]), TreeFixture.root(3),
        ])
      ).tree)
    let expected = Spacer(minLength: 0)
      .background(Color(argb: 0xff00_00ff), in: RoundedRectangle(cornerRadius: 0))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    #expect(
      try raster(
        NativeNodeView(node: #require(tree.root), activate: { _ in }).frame(width: 180, height: 100)
      )
      .matches(raster(expected.frame(width: 180, height: 100))))
  }

  @Test func directionalPaddingAndBackgroundOrderMatchNativeSwiftUI() throws {
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      let paddedBackground = try renderView(
        [
          TreeFixture.symbol(1, name: "star.fill", size: 18), TreeFixture.padding(2),
          TreeFixture.background(3), TreeFixture.children(2, [1]), TreeFixture.children(3, [2]),
        ], root: 3)
      let backgroundPadded = try renderView(
        [
          TreeFixture.symbol(1, name: "star.fill", size: 18), TreeFixture.padding(2),
          TreeFixture.background(3), TreeFixture.children(3, [1]), TreeFixture.children(2, [3]),
        ], root: 2)
      let first = try raster(paddedBackground, direction)
      let second = try raster(backgroundPadded, direction)
      #expect(
        first.matches(
          try raster(
            modifierSymbol.padding(nativeInsets).background(
              nativeBlue,
              in: RoundedRectangle(cornerRadius: 8, style: .continuous)), direction)))
      #expect(
        second.matches(
          try raster(
            modifierSymbol.background(
              nativeBlue,
              in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            ).padding(nativeInsets), direction)))
      #expect(first.pixels != second.pixels)
    }
  }

  @Test func roundedClippingAndOpacityMatchNativeComposition() throws {
    for radius in [0.0, 10.0] {
      for antialiased in [false, true] {
        for opacity in [0.0, 0.45, 1.0] {
          let view = try renderView(
            [
              TreeFixture.spacer(1, minimum: 0), TreeFixture.layoutFrame(2, width: 80, height: 60),
              TreeFixture.background(3, color: 0x99ff_0000, radius: 0),
              TreeFixture.layoutFrame(4, width: 40, height: 30),
              TreeFixture.clip(5, radius: radius, antialiased: antialiased ? 1 : 0),
              TreeFixture.opacity(6, opacity), TreeFixture.children(2, [1]),
              TreeFixture.children(3, [2]), TreeFixture.children(4, [3]),
              TreeFixture.children(5, [4]), TreeFixture.children(6, [5]),
            ], root: 6)
          let expected = Spacer(minLength: 0).frame(width: 80, height: 60)
            .background(
              Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.6),
              in: RoundedRectangle(cornerRadius: 0, style: .continuous)
            )
            .frame(width: 40, height: 30)
            .clipShape(
              RoundedRectangle(cornerRadius: radius, style: .continuous),
              style: FillStyle(antialiased: antialiased)
            ).opacity(opacity)
          #expect(try raster(view).matches(raster(expected)))
        }
      }
    }
  }

  @Test func invalidModifierTransactionsCannotPublishPartialUpdates() throws {
    let initial = TreeFixture.frame([
      TreeFixture.symbol(1), TreeFixture.padding(2), TreeFixture.background(3),
      TreeFixture.clip(4), TreeFixture.opacity(5, 0.5), TreeFixture.children(2, [1]),
      TreeFixture.children(3, [2]), TreeFixture.children(4, [3]), TreeFixture.children(5, [4]),
      TreeFixture.root(5),
    ])
    let before = try NodeStore().staging(initial).tree
    let snapshot = before
    var corruptions = [
      TreeFixture.clip(4, antialiased: 2, update: true),
      TreeFixture.opacity(5, 1.01, update: true),
    ]
    for value in [Double.nan, Double.infinity, -Double.infinity] {
      corruptions += [
        TreeFixture.padding(2, leading: value, update: true),
        TreeFixture.padding(2, top: value, update: true),
        TreeFixture.padding(2, trailing: value, update: true),
        TreeFixture.padding(2, bottom: value, update: true),
      ]
    }
    for value in [-1, Double.nan, Double.infinity, -Double.infinity] {
      corruptions += [
        TreeFixture.background(3, radius: value, update: true),
        TreeFixture.clip(4, radius: value, update: true),
        TreeFixture.opacity(5, value, update: true),
      ]
    }
    for id: UInt64 in [2, 3, 4, 5] { corruptions.append(TreeFixture.children(id, [])) }
    for operation in [
      TreeFixture.padding(2, update: true), TreeFixture.background(3, update: true),
      TreeFixture.clip(4, update: true), TreeFixture.opacity(5, 0.5, update: true),
    ] {
      for count in 0..<operation.body.count {
        corruptions.append(
          WireOperation(opcode: operation.opcode, body: operation.body.prefix(count)))
      }
    }
    for corruption in corruptions {
      #expect(throws: (any Error).self) {
        try before.staging(
          TreeFixture.frame(
            [
              TreeFixture.symbol(1, name: "star.fill", update: true), corruption,
            ], base: 1, revision: 2))
      }
      #expect(before == snapshot)
    }
  }
}

@MainActor private func renderView(_ operations: [WireOperation], root: UInt64) throws -> some View
{
  let model = RenderTree()
  model.commit(
    try NodeStore().staging(TreeFixture.frame(operations + [TreeFixture.root(root)])).tree)
  return NativeNodeView(node: try #require(model.root), activate: { _ in })
}

@MainActor private var modifierSymbol: some View {
  Image(systemName: "star.fill").font(.system(size: 18))
    .symbolRenderingMode(.monochrome).foregroundStyle(Color(.sRGB, red: 1, green: 0, blue: 0))
}

private let nativeInsets = EdgeInsets(top: 8, leading: 12, bottom: 6, trailing: 4)
private let nativeBlue = Color(.sRGB, red: 32.0 / 255, green: 96.0 / 255, blue: 160.0 / 255)

extension NativeRuntimeTests {
  @Test @MainActor func realModifierUpdatesRetainNativeNodes() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "modifiers")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let before = try FrameState().staging(WireFrame.decode(output.bytes))
      let model = RenderTree()
      model.commit(before.tree)
      let surface = try #require(model.nodes.values.first { $0.kind == NodeKindId.opacity })
      let nodes = model.nodes
      #expect(
        try raster(NativeNodeView(node: surface, activate: { _ in })).matches(
          raster(
            modifierSymbol.padding(nativeInsets).background(
              nativeBlue,
              in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)).opacity(0.7))))
      let button = try #require(before.tree.nodes.values.first { $0.kind == NodeKindId.button })
      let handler = try #require(button.bindings[EventTagId.press])
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      let press = NativeEvent(
        sequence: 1, displayedRevision: before.tree.revision,
        nodeID: button.id, handlerID: handler)
      let update = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: before.tree.epoch, events: [press]))
      model.commit(try before.staging(WireFrame.decode(update.bytes)).tree)
      for (id, old) in nodes { #expect(model.nodes[id] === old) }
      #expect(
        try raster(NativeNodeView(node: surface, activate: { _ in })).matches(
          raster(
            modifierSymbol.padding(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 2))
              .background(
                Color(.sRGB, red: 0, green: 1, blue: 0),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
              )
              .clipShape(
                RoundedRectangle(cornerRadius: 6, style: .continuous),
                style: FillStyle(antialiased: false)
              ).opacity(0.4))))
      try await runtime.acknowledge(update, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryModifiersRenderInBothLayoutDirections() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "gallery-modifiers")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      let kinds = Set(state.tree.nodes.values.map(\.kind))
      #expect(
        kinds.isSuperset(of: [
          NodeKindId.padding, NodeKindId.background, NodeKindId.clip, NodeKindId.opacity,
        ]))
      let model = RenderTree()
      model.commit(state.tree)
      let root = try #require(model.root)
      var results: [ViewRaster] = []
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        let rendered = try raster(
          NativeNodeView(node: root, activate: { _ in })
            .padding(24).frame(width: 360).environment(\.colorScheme, .light), direction)
        #expect(rendered.width == 376)  // 360-point frame plus the raster helper's 8-point border.
        #expect(rendered.height > 200)
        results.append(rendered)
        if let directory = ProcessInfo.processInfo.environment["BONSAI_RENDER_ARTIFACT_DIRECTORY"] {
          let url = URL(fileURLWithPath: directory, isDirectory: true)
          try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
          let suffix = direction == .leftToRight ? "ltr" : "rtl"
          try rendered.write(to: url.appendingPathComponent("gallery-modifiers-\(suffix).png"))
        }
      }
      #expect(results[0].width == results[1].width && results[0].height == results[1].height)
      #expect(results[0].pixels != results[1].pixels)
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
