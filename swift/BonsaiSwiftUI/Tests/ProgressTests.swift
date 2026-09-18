import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func progress(
    _ id: UInt64 = 1, value: Double? = nil, style: UInt8 = 2, update: Bool = false
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
      [TreeFixture.progress(style: 3, update: true)], [bindings],
      [TreeFixture.text(2, "Invalid child"), TreeFixture.children(1, [2])],
    ] {
      #expect(throws: (any Error).self) {
        try initial.staging(TreeFixture.frame(operations, base: 1, revision: 2))
      }
    }
    let update = TreeFixture.progress(value: 1, style: 0, update: true)
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
        for identifier in ["progress-linear", "progress-automatic"] {
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
