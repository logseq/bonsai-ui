import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func progress(
    _ id: UInt64 = 1, value: Double? = nil, style: UInt8 = 0, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) { writer in
      writer.integer(id)
      writer.integer(UInt16(10))
      if update { writer.integer(UInt64(3)) }
      writer.integer(UInt8(value == nil ? 0 : 1))
      if let value { writer.integer(value.bitPattern) }
      writer.integer(style)
      if !update { writer.integer(UInt16(0)) }
    }
  }
}

struct ProgressTests {
  @Test func progressRejectsInvalidValuesStylesBindingsAndChildrenAtomically() throws {
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.progress(value: 0.25), TreeFixture.root(1),
      ])
    ).tree
    for invalid in [-0.01, 1.01, Double.nan, .infinity, -.infinity] {
      #expect(throws: (any Error).self) {
        try initial.staging(
          TreeFixture.frame(
            [TreeFixture.progress(value: invalid, update: true)], base: 1, revision: 2))
      }
    }
    let bindings = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(1))
      $0.integer(UInt16(EventTagId.press))
      $0.integer(UInt64(3))
    }
    for operations in [
      [TreeFixture.progress(style: 2, update: true)], [bindings],
      [TreeFixture.text(2, "Invalid child"), TreeFixture.children(1, [2])],
    ] {
      #expect(throws: (any Error).self) {
        try initial.staging(TreeFixture.frame(operations, base: 1, revision: 2))
      }
    }
    let update = TreeFixture.progress(value: 1, style: 1, update: true)
    for length in 0..<update.body.count {
      #expect(throws: (any Error).self) {
        try initial.staging(
          TreeFixture.frame(
            [
              WireOperation(opcode: update.opcode, body: update.body.prefix(length))
            ], base: 1, revision: 2))
      }
    }
    #expect(initial.revision == 1 && initial.nodes.count == 1)
  }

  @Test @MainActor func linearProgressFillsFromTheNativeLeadingEdge() throws {
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.progress(value: 0.25), TreeFixture.root(1),
        ])
      ).tree)
    let node = try #require(tree.root)
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      let output = try raster(
        NativeNodeView(node: node, activate: { _ in })
          .tint(.black).frame(width: 160, height: 40).environment(\.colorScheme, .light), direction)
      let blackX = stride(from: 0, to: output.pixels.count, by: 4).filter {
        output.pixels[$0] < 80 && output.pixels[$0 + 1] < 80 && output.pixels[$0 + 2] < 80
      }.map { ($0 / 4) % output.width }
      #expect(!blackX.isEmpty)
      let center = Double(blackX.reduce(0, +)) / Double(max(1, blackX.count))
      #expect(
        direction == .leftToRight
          ? center < Double(output.width) / 2 : center > Double(output.width) / 2)
    }
  }

  @Test @MainActor func determinateProgressPaintsFractionAndRetainsIdentityAcrossModes() throws {
    for style in UInt8(0)...1 {
      let tree = RenderTree()
      var store = try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.progress(value: 0, style: style), TreeFixture.root(1),
        ])
      ).tree
      tree.commit(store)
      let node = try #require(tree.root)
      var amounts: [Int] = []
      for (index, value) in [0.0, 0.25, 0.75, 1.0].enumerated() {
        store = try store.staging(
          TreeFixture.frame(
            [
              TreeFixture.progress(value: value, style: style, update: true)
            ], base: UInt64(index + 1), revision: UInt64(index + 2))
        ).tree
        tree.commit(store)
        let output = try raster(
          NativeNodeView(node: node, activate: { _ in })
            .tint(.black).frame(width: 160, height: 40).environment(\.colorScheme, .light))
        let black = stride(from: 0, to: output.pixels.count, by: 4).filter {
          output.pixels[$0] < 80 && output.pixels[$0 + 1] < 80 && output.pixels[$0 + 2] < 80
        }.count
        amounts.append(black)
        #expect(tree.root === node)
      }
      #expect(amounts[0] == 0)
      #expect(amounts[1] > 10)
      #expect(amounts[2] > amounts[1] * 2)
      #expect(amounts[3] > amounts[2])
      let next = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.progress(style: style == 0 ? 1 : 0, update: true)
          ], base: 5, revision: 6)
      ).tree
      tree.commit(next)
      #expect(tree.root === node)
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryProgressUpdatesValuesAndIndeterminateMode() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-progress")
      let root = try #require(session.tree.root)
      let host = NSHostingView(
        rootView: NativeNodeView(node: root, activate: { session.activate($0) })
          .environment(\.locale, Locale(identifier: "en_US"))
          .environment(\.scenePhase, .active))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 220), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      let original = session.tree.nodes.values.filter { $0.kind == 10 }
      #expect(original.count == 2)
      for percent in ["25%", "75%", nil, "100%"] {
        try await settleAccessibility(host)
        #expect(try await session.presented(#require(session.ticket)))
        for identifier in ["progress-linear", "progress-circular"] {
          let element = try #require(
            accessibilityElements(host).first { $0.identifier == identifier })
          if let percent {
            #expect(element.role == "AXProgressIndicator")
            #expect(element.valueDescription == percent)
            #expect(element.minimum == 0 && element.maximum == 1)
            #expect(element.numericValue == Double(percent.dropLast())! / 100)
          } else {
            #expect(element.role == "AXBusyIndicator")
            #expect(element.valueDescription == nil)
          }
        }
        #expect(original.allSatisfy { session.tree.nodes[$0.id.node] === $0 })
        if percent == nil {
          let first = try progressSnapshot(host)
          try await Task.sleep(for: .milliseconds(180))
          #expect(try progressSnapshot(host) != first)
          let revision = session.displayedRevision
          session.isActive = false
          try await settleAccessibility(host)
          let paused = try progressSnapshot(host)
          try await Task.sleep(for: .milliseconds(180))
          #expect(try progressSnapshot(host) == paused)
          #expect(session.displayedRevision == revision && session.ticket == nil)
          session.isActive = true

        }
        if percent != "100%" {
          let button = try #require(
            accessibilityElements(host).first { $0.identifier == "progress-advance" })
          #expect(button.press())
          #expect(try await session.refresh())
        }
      }
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

@MainActor private func progressSnapshot(_ host: NSView) throws -> Data {
  host.layoutSubtreeIfNeeded()
  host.displayIfNeeded()
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  return try #require(bitmap.representation(using: .png, properties: [:]))
}
