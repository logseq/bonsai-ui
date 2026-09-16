import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func symbol(
    _ id: UInt64 = 1, name: String = "star", size: Double? = 40,
    color: UInt32? = 0xffff_0000, rendering: UInt8 = 0, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(NodeKindId.symbol))
      if update { $0.integer(UInt64(15)) }
      $0.integer(UInt32(name.utf8.count))
      $0.bytes.append(contentsOf: name.utf8)
      $0.integer(UInt8(size == nil ? 0 : 1))
      if let size { $0.integer(size.bitPattern) }
      $0.integer(UInt8(color == nil ? 0 : 1))
      if let color { $0.integer(color) }
      $0.integer(rendering)
      if !update {
        $0.integer(UInt16(0))
      }
    }
  }
}

@MainActor
struct SymbolTests {
  @Test func symbolsRenderLikeNativeImagesWithDefaultSizeAndInheritedColor() throws {
    for (mode, nativeMode) in [
      (UInt8(0), SymbolRenderingMode.monochrome), (1, .hierarchical), (2, .multicolor),
    ] {
      for explicit in [true, false] {
        let model = RenderTree()
        let frame = TreeFixture.frame([
          TreeFixture.symbol(
            name: "person.crop.circle.badge.checkmark", size: explicit ? 40 : nil,
            color: explicit ? 0xffff_0000 : nil, rendering: mode), TreeFixture.root(1),
        ])
        model.commit(try NodeStore().staging(frame).tree)
        let root = try #require(model.root)
        let actual = try symbolImage(
          NativeNodeView(node: root, activate: { _ in })
            .font(.system(size: 27)).foregroundStyle(Color.blue))
        let expected = try symbolImage(
          Image(systemName: "person.crop.circle.badge.checkmark")
            .font(.system(size: explicit ? 40 : 19))
            .symbolRenderingMode(nativeMode)
            .foregroundStyle(explicit ? Color(.sRGB, red: 1, green: 0, blue: 0) : Color.blue))
        #expect(
          actual.matches(expected), "Rendering mode \(mode), explicit style \(explicit)")
      }
    }
  }

  @Test func invalidSymbolsCannotPublishPartialUpdates() throws {
    let before = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.create(1), TreeFixture.text(2, "Original"), TreeFixture.symbol(3),
        TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
      ])
    ).tree
    let snapshot = before
    var corruptions = [
      TreeFixture.symbol(3, name: "", update: true),
      TreeFixture.symbol(3, name: "star\0fill", update: true),
      TreeFixture.symbol(3, name: "star fill", update: true),
      TreeFixture.symbol(3, name: "bonsai.this.symbol.does.not.exist", update: true),
      TreeFixture.symbol(3, rendering: 4, update: true),
      TreeFixture.children(3, [2]),
    ]
    for size in [0, -1, Double.nan, .infinity, -.infinity] {
      corruptions.append(TreeFixture.symbol(3, size: size, update: true))
    }
    let valid = TreeFixture.symbol(3, update: true)
    for count in 0..<valid.body.count {
      corruptions.append(WireOperation(opcode: valid.opcode, body: valid.body.prefix(count)))
    }
    for corruption in corruptions {
      #expect(throws: (any Error).self) {
        try before.staging(
          TreeFixture.frame(
            [
              TreeFixture.text(2, "Must not leak", update: true), corruption,
            ], base: 1, revision: 2))
      }
      #expect(before == snapshot)
    }
  }
}

@MainActor
private func symbolImage(_ content: some View) throws -> ViewRaster {
  let result = try raster(content, background: .clear)
  #expect(result.width > 16 && result.height > 16)
  return result
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGallerySymbolSectionRendersThroughNativeRuntime() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "gallery-symbols")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      let symbols = state.tree.nodes.values.compactMap { node -> RenderSymbol? in
        if case .symbol(let symbol) = node.properties { return symbol }
        return nil
      }
      #expect(symbols.count == 10)
      #expect(Set(symbols.map(\.rendering)) == [0, 1, 2, 3])
      #expect(symbols.contains { $0.size == nil && $0.color == nil })
      let model = RenderTree()
      model.commit(state.tree)
      let root = try #require(model.root)
      let content = NativeNodeView(node: root, activate: { _ in })
        .padding(24).frame(width: 360).background(Color.white).environment(\.colorScheme, .light)
      let png = try symbolImage(content)
      if let directory = ProcessInfo.processInfo.environment["BONSAI_RENDER_ARTIFACT_DIRECTORY"] {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try png.write(to: url.appendingPathComponent("gallery-symbols.png"))
      }
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test @MainActor func realSymbolButtonUpdatesWithoutReplacingItsNativeNode() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "symbols")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let before = try FrameState().staging(WireFrame.decode(output.bytes))
      let model = RenderTree()
      model.commit(before.tree)
      let symbol = try #require(model.nodes.values.first { $0.kind == NodeKindId.symbol })
      let button = try #require(before.tree.nodes.values.first { $0.kind == NodeKindId.button })
      let handler = try #require(button.bindings[EventTagId.press])
      let initialImage = try symbolImage(NativeNodeView(node: symbol, activate: { _ in }))
      #expect(
        initialImage.matches(
          try symbolImage(
            Image(systemName: "star").font(.system(size: 32))
              .symbolRenderingMode(.monochrome)
              .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 1)))))
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      let press = NativeEvent(
        sequence: 1, displayedRevision: before.tree.revision,
        nodeID: button.id, handlerID: handler)
      let update = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: before.tree.epoch, events: [press]))
      let after = try before.staging(WireFrame.decode(update.bytes))
      model.commit(after.tree)
      #expect(model.nodes[symbol.id.node] === symbol)
      let updatedImage = try symbolImage(NativeNodeView(node: symbol, activate: { _ in }))
      #expect(updatedImage.pixels != initialImage.pixels)
      #expect(
        updatedImage.matches(
          try symbolImage(
            Image(systemName: "star.fill").font(.system(size: 40))
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(Color(.sRGB, red: 1, green: 0, blue: 0)))))
      try await runtime.acknowledge(update, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
