import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualPageLayoutPinsControlsAndRetainsItsScrollingBody() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-page-layout")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { _ = session.activate($0) }))
      host.sizingOptions = []
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 480, height: 400),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func settle() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
        try await settleAccessibility(host)
      }
      func element(_ title: String) throws -> AccessibilityElement {
        try #require(
          accessibilityElements(host).first { $0.role == "AXButton" && $0.label == title })
      }
      func rect(_ title: String) throws -> CGRect {
        let object = try element(title).object
        let selector = NSSelectorFromString("accessibilityFrame")
        #expect(object.responds(to: selector))
        typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
      }
      func scroll() throws -> NSScrollView {
        var pending: [NSView] = [host]
        while let view = pending.popLast() {
          if let scroll = view as? NSScrollView { return scroll }
          pending.append(contentsOf: view.subviews)
        }
        throw NSError(domain: "PageLayoutTests", code: 1)
      }
      func count(_ n: Int) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == "Page actions: \(n)" }
          return false
        }
      }
      try await settle()
      let native = try scroll()
      let original = session.tree.nodes
      let bodySize = native.contentView.bounds.size
      #expect(bodySize.height > 200 && bodySize.height < 400)
      let footerBefore = try rect("Footer action")
      #expect(try rect("Header action").minY > footerBefore.maxY)
      #expect(try rect("Floating action").minY > footerBefore.maxY)
      #expect(try element("Header action").press())
      #expect(try element("Header action").press())
      #expect(try element("Footer action").press())
      #expect(try element("Floating action").press())
      #expect(try element("Row 0").press())
      try await settle()
      #expect(count(5))
      native.contentView.scroll(to: CGPoint(x: 0, y: 400))
      native.reflectScrolledClipView(native.contentView)
      try await settle()
      #expect(abs(native.documentVisibleRect.minY - 400) < 1)
      #expect(try rect("Footer action") == footerBefore)
      #expect(try element("Resize footer").press())
      try await settle()
      #expect(try scroll() === native)
      #expect(abs(bodySize.height - native.contentView.bounds.height - 40) < 1)
      #expect(abs(native.documentVisibleRect.minY - 400) < 1)
      #expect(try rect("Floating action").minY > rect("Footer action").maxY)
      window.setContentSize(CGSize(width: 600, height: 500))
      try await settle()
      #expect(abs(native.contentView.bounds.width - bodySize.width - 120) < 1)
      #expect(abs(native.contentView.bounds.height - bodySize.height - 60) < 1)
      #expect(abs(native.documentVisibleRect.minY - 400) < 1)
      #expect(original.allSatisfy { session.tree.nodes[$0.key] === $0.value })
      #expect(try element("Resize footer").press())
      try await settle()
      #expect(abs(native.contentView.bounds.height - bodySize.height - 100) < 1)
      #expect(try element("Footer action").press())
      try await settle()
      #expect(count(6))
      let floating = try #require(
        session.tree.nodes.values.first {
          $0.kind == NodeKindId.button
            && $0.children.contains {
              if case .text(let text) = $0.properties { return text.value == "Floating action" }
              return false
            }
        })
      session.isVisible = false
      #expect(!session.activate(floating))
      session.isVisible = true
      try await settle()
      #expect(abs(native.documentVisibleRect.minY - 400) < 1)
      await session.close()
      #expect(!session.activate(floating))
    } catch {
      await session.close()
      throw error
    }
  }
}
