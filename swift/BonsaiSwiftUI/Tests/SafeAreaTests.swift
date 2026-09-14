import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func ignoresSafeArea(
    _ id: UInt64 = 1, regions: UInt8 = 0, edges: UInt8 = 15, update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: 11, mask: 3, update: update) {
      $0.integer(regions)
      $0.integer(edges)
    }
  }
  static func safeAreaPadding(
    _ id: UInt64 = 1, leading: Double = 12, top: Double = 8,
    trailing: Double = 20, bottom: Double = 14, update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: 12, mask: 1, update: update) {
      for value in [leading, top, trailing, bottom] { $0.integer(value.bitPattern) }
    }
  }
}

struct SafeAreaTests {
  @Test func safeAreaModifiersRejectMalformedFieldsAndStructuralChanges() throws {
    for create in [TreeFixture.ignoresSafeArea(), TreeFixture.safeAreaPadding()] {
      let initial = try NodeStore().staging(
        TreeFixture.frame([
          create, TreeFixture.text(2, "Protected content"), TreeFixture.children(1, [2]),
          TreeFixture.root(1),
        ])
      ).tree
      let bindings = TreeFixture.operation(OperationId.updateEventBindings) {
        $0.integer(UInt64(1))
        $0.integer(UInt16(1))
        $0.integer(UInt16(EventTagId.press))
        $0.integer(UInt64(3))
      }
      for operation in [bindings, TreeFixture.children(1, [])] {
        #expect(throws: (any Error).self) {
          try initial.staging(TreeFixture.frame([operation], base: 1, revision: 2))
        }
      }
      let update =
        create.body[8] == 11
        ? TreeFixture.ignoresSafeArea(update: true) : TreeFixture.safeAreaPadding(update: true)
      for length in 0..<update.body.count {
        #expect(throws: (any Error).self) {
          try initial.staging(
            TreeFixture.frame(
              [
                WireOperation(opcode: update.opcode, body: update.body.prefix(length))
              ], base: 1, revision: 2))
        }
      }
      #expect(initial.revision == 1)
    }
    for invalid in [
      TreeFixture.ignoresSafeArea(regions: 3), TreeFixture.ignoresSafeArea(edges: 16),
      TreeFixture.safeAreaPadding(leading: .nan), TreeFixture.safeAreaPadding(top: .infinity),
    ] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(
          TreeFixture.frame([
            invalid, TreeFixture.text(2, "Content"), TreeFixture.children(1, [2]),
            TreeFixture.root(1),
          ]))
      }
    }
  }

  @Test @MainActor func safeAreaPaddingMatchesNativeDirectionalAndNegativeInsets() throws {
    for leading in [12.0, -4.0] {
      let tree = RenderTree()
      tree.commit(
        try NodeStore().staging(
          TreeFixture.frame([
            TreeFixture.safeAreaPadding(leading: leading),
            TreeFixture.background(2, color: 0xff00_00ff, radius: 0),
            TreeFixture.layoutFrame(3, maxWidth: .infinity, maxHeight: .infinity),
            TreeFixture.text(4, ""),
            TreeFixture.children(1, [2]), TreeFixture.children(2, [3]),
            TreeFixture.children(3, [4]), TreeFixture.root(1),
          ])
        ).tree)
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        let actual = NativeNodeView(node: try #require(tree.root), activate: { _ in })
        let expected = Text("").frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color(argb: 0xff00_00ff), in: RoundedRectangle(cornerRadius: 0))
          .safeAreaPadding(EdgeInsets(top: 8, leading: leading, bottom: 14, trailing: 20))
        #expect(
          try raster(actual.frame(width: 180, height: 100), direction)
            .matches(raster(expected.frame(width: 180, height: 100), direction)))
      }
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGallerySafeAreasUseNativeTitlebarInsetsAndRetainChildren()
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-safe-area")
      let root = try #require(session.tree.root)
      let host = NSHostingView(
        rootView: NativeNodeView(node: root, activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
        styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
      host.sizingOptions = []
      window.titlebarAppearsTransparent = true
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      #expect(host.safeAreaInsets.top > 0)
      #expect(try await session.presented(#require(session.ticket)))
      let original = session.tree.nodes
      let protected = try safeAreaBlueBounds(host)
      func advance() async throws {
        let button = try #require(
          accessibilityElements(host).first { $0.identifier == "safe-area-advance" })
        #expect(button.press())
        #expect(try await session.refresh())
        try await settleAccessibility(host)
        #expect(try await session.presented(#require(session.ticket)))
      }
      try await advance()
      let extended = try safeAreaBlueBounds(host)
      #expect(extended.height > protected.height + 10)
      try await advance()
      let keyboardOnly = try safeAreaBlueBounds(host)
      #expect(abs(keyboardOnly.height - protected.height) < 1)
      try await advance()
      let allRegions = try safeAreaBlueBounds(host)
      #expect(abs(allRegions.height - extended.height) < 1)
      try await advance()
      let padded = try safeAreaBlueBounds(host)
      #expect(abs(extended.width - padded.width - 32) < 1)
      #expect(abs(extended.height - padded.height - 22) < 1)
      #expect(original.allSatisfy { session.tree.nodes[$0.key] === $0.value })
      window.setContentSize(NSSize(width: 460, height: 330))
      try await settleAccessibility(host)
      let resized = try safeAreaBlueBounds(host)
      #expect(abs(resized.width - padded.width - 100) < 1)
      #expect(abs(resized.height - padded.height - 50) < 1)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

@MainActor private func safeAreaBlueBounds(_ host: NSView) throws -> CGRect {
  host.layoutSubtreeIfNeeded()
  host.displayIfNeeded()
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  let image = try #require(bitmap.cgImage)
  let context = try #require(
    CGContext(
      data: nil, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ))
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
  var minimumX = image.width
  var minimumY = image.height
  var maximumX = -1
  var maximumY = -1
  for y in 0..<image.height {
    for x in 0..<image.width {
      let offset = (y * image.width + x) * 4
      if pixels[offset] < 60 && pixels[offset + 1] < 60 && pixels[offset + 2] > 200
        && pixels[offset + 3] > 240
      {
        minimumX = min(minimumX, x)
        maximumX = max(maximumX, x)
        minimumY = min(minimumY, y)
        maximumY = max(maximumY, y)
      }
    }
  }
  #expect(maximumX >= minimumX && maximumY >= minimumY)
  let scale = host.bounds.width / CGFloat(image.width)
  return CGRect(
    x: CGFloat(minimumX) * scale, y: CGFloat(minimumY) * scale,
    width: CGFloat(maximumX - minimumX + 1) * scale,
    height: CGFloat(maximumY - minimumY + 1) * scale)
}
