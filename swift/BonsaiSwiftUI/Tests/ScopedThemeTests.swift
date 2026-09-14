import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func scopedThemeGalleryRetainsActionsAndNativeInheritance() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    func contains(_ text: String, _ node: RenderNodeState) -> Bool {
      if case .text(let value) = node.properties, value.value == text { return true }
      return node.children.contains { contains(text, $0) }
    }
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          if case .button = $0.properties { return contains(title, $0) }
          return false
        })
    }
    func text(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          if case .text(let value) = $0.properties { return value.value == title }
          return false
        })
    }
    do {
      try await session.start(entrypoint: "native-theme")
      let root = try #require(session.tree.root)
      let scopedAction = try button("Scoped action")
      let outsideAction = try button("Outside action")
      let scope = try #require(
        session.tree.nodes.values.first {
          if case .environment(let value) = $0.properties { return value.mode == 2 }
          return false
        })
      let nested = try #require(
        session.tree.nodes.values.first {
          if case .environment(let value) = $0.properties { return value.mode == 1 }
          return false
        })
      let outside = try text("Outside sample")
      let outsidePixels = try raster(
        NativeNodeView(node: outside, activate: { _ in }).environment(\.colorScheme, .light))
      let hosting = NSHostingView(
        rootView:
          NativeNodeView(node: root, activate: { session.activate($0) })
          .environment(\.colorScheme, .light).frame(width: 540, height: 620))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 540, height: 620),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = hosting
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(hosting)
      #expect(try await session.presented(#require(session.ticket)))
      func press(_ title: String) async throws {
        let native = try #require(
          accessibilityElements(hosting).first {
            $0.role == "AXButton" && $0.label == title
          })
        _ = native.press()
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
        try await settleAccessibility(hosting)
      }
      func expectScope(explicit: Bool, font: Bool, size: UInt8) throws {
        guard case .environment(let values) = scope.properties else {
          Issue.record("Scoped theme disappeared")
          return
        }
        #expect(values.mode == (explicit ? 2 : 0))
        #expect(values.tint == (explicit ? 0xff80_5ad5 : nil))
        #expect(values.fontFamily == (font ? "Menlo" : nil))
        #expect(values.controlSize == size)
        let nativeSize: ControlSize = [.mini, .small, .regular, .large, .extraLarge][Int(size)]
        let child = NativeNodeView(node: try #require(scope.children.first), activate: { _ in })
          .environment(\.colorScheme, explicit ? .dark : .light)
          .environment(\.bonsaiFontFamily, font ? "Menlo" : nil)
          .controlSize(nativeSize)
        let reference = explicit ? AnyView(child.tint(Color(argb: 0xff80_5ad5))) : AnyView(child)
        #expect(
          try raster(
            NativeNodeView(node: scope, activate: { _ in }).environment(\.colorScheme, .light)
          ).matches(raster(reference)))
        guard case .environment(let nestedValues) = nested.properties else {
          Issue.record("Nested theme disappeared")
          return
        }
        #expect(nestedValues.mode == 1 && nestedValues.fontFamily == nil)
        #expect(try button("Scoped action") === scopedAction)
        #expect(try button("Outside action") === outsideAction)
        #expect(try text("Outside sample") === outside)
        #expect(
          try raster(
            NativeNodeView(node: outside, activate: { _ in }).environment(\.colorScheme, .light)
          ).matches(outsidePixels))
      }
      try expectScope(explicit: true, font: false, size: 2)
      try await press("Scoped action")
      try await press("Outside action")
      try await press("Toggle scoped theme")
      try expectScope(explicit: false, font: false, size: 2)
      try await press("Toggle scoped font")
      try expectScope(explicit: false, font: true, size: 2)
      for size: UInt8 in [3, 4, 0, 1, 2] {
        try await press("Cycle control size")
        try expectScope(explicit: false, font: true, size: size)
      }
      try await press("Toggle scoped theme")
      try expectScope(explicit: true, font: true, size: 2)
      try await press("Toggle scoped font")
      try await press("Scoped action")
      try expectScope(explicit: true, font: false, size: 2)
      #expect(contains("Scoped actions: 2", root))
      #expect(contains("Outside actions: 1", root))
      session.isVisible = false
      #expect(!session.activate(scopedAction))
      session.isVisible = true
      try await press("Outside action")
      #expect(contains("Outside actions: 2", root))
      await session.close()
      #expect(!session.activate(scopedAction))
    } catch {
      await session.close()
      throw error
    }
  }
}
