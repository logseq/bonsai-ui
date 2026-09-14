import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func environment(
    mode: UInt8 = 0, controlSize: UInt8 = 2,
    font: String? = "Inter"
  ) -> WireOperation {
    operation(OperationId.setApplicationTheme) {
      $0.integer(UInt8(0))  // No window title.
      $0.integer(mode)
      $0.integer(UInt8(1))
      $0.integer(UInt32(0xff67_50a4))
      $0.integer(UInt8(font == nil ? 0 : 1))
      if let font {
        $0.integer(UInt32(font.utf8.count))
        $0.bytes.append(contentsOf: font.utf8)
      }
      $0.integer(controlSize)
    }
  }
}

struct ViewEnvironmentTests {
  @Test func scopedEnvironmentUsesTheSameWireValues() throws {
    let scoped = TreeFixture.operation(OperationId.createNode) {
      $0.integer(UInt64(5))
      $0.integer(UInt16(NodeKindId.theme))
      $0.bytes.append(TreeFixture.environment(mode: 2, controlSize: 3).body.dropFirst())
      $0.integer(UInt16(0))
    }
    let frame = TreeFixture.frame(
      TreeFixture.initial.operations + [
        scoped, TreeFixture.children(5, [1]), TreeFixture.root(5), TreeFixture.environment(),
      ])
    let state = try FrameState().staging(frame)
    #expect(state.tree.root == 5)
    #expect(state.tree.nodes[5]?.kind == NodeKindId.theme)
    #expect(state.tree.nodes[5]?.children == [1])
  }

  @Test func completeFrameStagesEnvironmentAndTreeAtomically() throws {
    let initial = TreeFixture.frame(TreeFixture.initial.operations + [TreeFixture.environment()])
    let state = try FrameState().staging(initial)
    #expect(
      state.application?.environment
        == ViewEnvironment(
          mode: 0, tint: 0xff67_50a4, fontFamily: "Inter", controlSize: 2))
    let updated = try state.staging(
      TreeFixture.frame(
        [
          TreeFixture.environment(mode: 2, controlSize: 3, font: nil)
        ], base: 1, revision: 2))
    #expect(updated.tree.nodes == state.tree.nodes)
    #expect(updated.application?.environment.mode == 2)
    #expect(state.application?.environment.mode == 0)
    let inherited = try updated.staging(TreeFixture.frame([], base: 2, revision: 3))
    #expect(inherited.application == updated.application)
  }

  @Test func invalidOrMissingMetadataCannotPublishPartialTree() throws {
    let frame = TreeFixture.frame(TreeFixture.initial.operations + [TreeFixture.environment()])
    let state = try FrameState().staging(frame)
    let snapshot = state
    for operation in [
      TreeFixture.environment(mode: 3), TreeFixture.environment(controlSize: 5),
      TreeFixture.environment(font: "  "), TreeFixture.environment(font: "a\0b"),
      WireOperation(opcode: OperationId.hostRequest, body: Data()),
      WireOperation(opcode: OperationId.runtimeNotification, body: Data()),
    ] {
      #expect(throws: (any Error).self) {
        try state.staging(
          TreeFixture.frame(
            [
              TreeFixture.text(2, "Must not publish", update: true), operation,
            ], base: 1, revision: 2))
      }
      #expect(state == snapshot)
    }
    for operations in [
      TreeFixture.initial.operations,
      frame.operations + [TreeFixture.environment()],
    ] {
      #expect(throws: (any Error).self) { try FrameState().staging(TreeFixture.frame(operations)) }
    }
    let metadata = TreeFixture.environment()
    for count in 0..<metadata.body.count {
      #expect(throws: (any Error).self) {
        try FrameState().staging(
          TreeFixture.frame(
            TreeFixture.initial.operations + [
              WireOperation(opcode: metadata.opcode, body: metadata.body.prefix(count))
            ]))
      }
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func realCounterIncludesOnlyValidatedSwiftUIEnvironment() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(initial.bytes))
      #expect(state.application?.title == "Counter")
      #expect(state.application?.environment.tint == 0xff67_50a4)
      #expect(state.application?.environment.controlSize == 2)
      let model = RenderTree()
      model.commit(state.tree)
      let root = try #require(model.root)
      let environment = try #require(state.application?.environment)
      let content = NativeNodeView(node: root, activate: { _ in })
        .modifier(SwiftUIEnvironmentModifier(values: environment))
        .padding(32).frame(width: 360, height: 240)
        .background(Color(nsColor: .windowBackgroundColor))
      let renderer = ImageRenderer(content: content)
      renderer.scale = 2
      let image = try #require(renderer.cgImage)
      #expect(image.width == 720)
      #expect(image.height == 480)
      if let directory = ProcessInfo.processInfo.environment["BONSAI_RENDER_ARTIFACT_DIRECTORY"] {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("counter-environment.png"), options: .atomic)
      }
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
