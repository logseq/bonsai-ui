import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

private func surfacePayload(
  mode: UInt8 = 1, radius: Double = 20, colors: [UInt32] = [0xffff_0000, 0xff00_00ff],
  presentation: Bool = false, opacity: Double = 1
) -> Data {
  var writer = WireWriter()
  writer.integer(mode)
  writer.integer(UInt8(colors.count))
  writer.integer(UInt8(presentation ? 1 : 0))
  writer.integer(UInt8(0))
  for value in [radius, 12.0, 0.0, 5.0, 1.0, opacity] { writer.integer(value.bitPattern) }
  writer.integer(UInt32(0x3300_0000))
  writer.integer(UInt32(0x66ff_ffff))
  for color in colors { writer.integer(color) }
  return writer.bytes
}

struct SurfaceTests {
  @Test @MainActor func standardSurfaceAcceptsAllFillsAndRequiresOneChild() throws {
    initializeAccessibilityApplication()
    let registry = BonsaiNativeViews().includingStandardViews()
    for mode: UInt8 in 0...5 {
      let colors: [UInt32] = (mode == 1 || mode == 2) ? [0xffff_0000, 0xff00_00ff] : [0x44ff_eecc]
      let prepared = try registry.prepare(
        RenderNativeView(
          kind: 8, version: 2, capabilities: [],
          payload: surfacePayload(mode: mode, colors: colors, presentation: true)))
      try prepared.definition.validateChildren(prepared.properties, 1)
      for count in [0, 2] {
        #expect(throws: TreeError.self) {
          try prepared.definition.validateChildren(prepared.properties, count)
        }
      }
    }
  }

  @Test @MainActor func rejectsMalformedSurfacesBeforeRendering() throws {
    let registry = BonsaiNativeViews().includingStandardViews()
    let valid = surfacePayload()
    _ = try registry.prepare(
      RenderNativeView(kind: 8, version: 2, capabilities: [], payload: valid))
    let invalid = [
      surfacePayload(opacity: -0.1), surfacePayload(opacity: 1.01),
      surfacePayload(opacity: .nan), surfacePayload(opacity: .infinity),
      surfacePayload(mode: 6), surfacePayload(radius: -.infinity), surfacePayload(radius: -1),
      surfacePayload(colors: []), surfacePayload(colors: [0xffff_ffff]), valid + Data([0]),
      Data(valid.dropLast()),
    ]
    for payload in invalid {
      #expect(throws: (any Error).self) {
        _ = try registry.prepare(
          RenderNativeView(kind: 8, version: 2, capabilities: [], payload: payload))
      }
    }
  }

  @Test @MainActor func gradientAndMaterialRenderAndRetainAccessibleChild() async throws {
    initializeAccessibilityApplication()
    for mode: UInt8 in [1, 3, 4, 5] {
      let payload = surfacePayload(
        mode: mode, colors: mode == 1 ? [0xffff_0000, 0xff00_00ff] : [0x44ff_eecc])
      let operation = TreeFixture.operation(OperationId.createNode) {
        $0.integer(UInt64(1))
        $0.integer(UInt16(NodeKindId.nativeWidget))
        $0.integer(UInt32(8))
        $0.integer(UInt16(2))
        $0.integer(UInt64(0))
        $0.integer(UInt32(payload.count))
        $0.bytes.append(payload)
        $0.integer(UInt16(1))
        $0.integer(UInt16(EventTagId.nativeEvent))
        $0.integer(UInt64(9))
      }
      let store = try NodeStore().staging(
        TreeFixture.frame([
          operation, TreeFixture.text(2, "Surface content"), TreeFixture.children(1, [2]),
          TreeFixture.root(1),
        ])
      ).tree
      let tree = RenderTree()
      try tree.validate(store)
      tree.commit(store)
      let root = try #require(tree.root)
      for scheme in [ColorScheme.light, .dark] {
        let view = NativeNodeView(node: root, activate: { _ in })
          .padding(20).frame(width: 240, height: 120)
          .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 120)
        try await settleAccessibility(host)
        #expect(
          accessibilityElements(host).contains {
            $0.label == "Surface content" || $0.value == "Surface content"
          })
        let renderer = ImageRenderer(content: view)
        #expect(renderer.cgImage != nil)
      }
      tree.commit(NodeStore())
    }
  }

  @Test @MainActor func reducedTransparencyPaintIsOpaqueUnderEitherBackdropAndAppearance() throws {
    for mode: UInt8 in [3, 4, 5] {
      let properties = try RenderSurface.decode(
        surfacePayload(mode: mode, colors: [0x22ff_ccaa], opacity: 0.4))
      for scheme in [ColorScheme.light, .dark] {
        for backdrop in [Color.red, Color.blue] {
          let view = NativeSurfacePaint(properties: properties, reduceTransparency: true)
            .frame(width: 80, height: 80).background(backdrop)
            .environment(\.colorScheme, scheme)
          let image = try #require(ImageRenderer(content: view).cgImage)
          let bitmap = NSBitmapImageRep(cgImage: image)
          let color = try #require(bitmap.colorAt(x: 40, y: 40)?.usingColorSpace(.sRGB))
          let expectedImage = try #require(
            ImageRenderer(
              content:
                Color(argb: 0xffff_ccaa).frame(width: 80, height: 80)
                .environment(\.colorScheme, scheme)
            ).cgImage)
          let expected = try #require(
            NSBitmapImageRep(cgImage: expectedImage)
              .colorAt(x: 40, y: 40)?.usingColorSpace(.sRGB))
          #expect(abs(color.redComponent - expected.redComponent) < 0.001)
          #expect(abs(color.greenComponent - expected.greenComponent) < 0.001)
          #expect(abs(color.blueComponent - expected.blueComponent) < 0.001)
          #expect(color.alphaComponent == 1)
        }
      }
    }
  }

  @Test @MainActor func standardSurfaceKindCannotBeReplaced() throws {
    var registry = BonsaiNativeViews()
    #expect(throws: BonsaiNativeViewError.self) {
      try registry.register(
        kind: 8, version: 2, decode: { _ in () },
        encodeEvent: { (_: Bool) in BonsaiNativeEvent(id: 1) },
        makeResource: { () }, dispose: { _ in }, content: { _ in Text("Override") })
    }
  }
}
