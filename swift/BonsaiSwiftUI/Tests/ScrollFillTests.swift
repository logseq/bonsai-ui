import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test(arguments: [false, true], [false, true]) @MainActor
  func actualScrollFillsRemainingSpaceWithoutCompressingLongContent(horizontal: Bool, rtl: Bool)
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(
        entrypoint: horizontal ? "native-scroll-fill-horizontal" : "native-scroll-fill")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root),
          activate: { _ = session.activate($0) }
        ).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
      host.sizingOptions = []
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 640, height: 540),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func settle() async throws {
        for _ in 0..<3 {
          _ = try await session.refresh()
          if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
          try await settleAccessibility(host)
        }
      }
      func button(_ label: String) throws -> AccessibilityElement {
        try #require(
          accessibilityElements(host).first { $0.role == "AXButton" && $0.label == label })
      }
      func frame(_ label: String) throws -> CGRect {
        let object = try button(label).object
        let selector = NSSelectorFromString("accessibilityFrame")
        typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
      }
      func scroll() throws -> NSScrollView {
        var pending: [NSView] = [host]
        while let view = pending.popLast() {
          if let scroll = view as? NSScrollView { return scroll }
          pending.append(contentsOf: view.subviews)
        }
        throw NSError(domain: "ScrollFillTests", code: 1)
      }
      func extent(_ rect: CGRect) -> Double { horizontal ? rect.width : rect.height }
      try await settle()
      let native = try scroll()
      func checkShort() throws {
        let available = extent(native.contentView.bounds)
        #expect(abs(extent(try frame("Fill content")) - (available - 120)) < 1)
        #expect(abs(extent(native.documentView!.frame) - available) < 1)
      }
      try checkShort()
      #expect(try button("Fill content").press())
      try await settle()
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let value) = $0.properties { return value.value == "Actions: 1" }
          return false
        })
      window.setContentSize(CGSize(width: 720, height: 620))
      try await settle()
      try checkShort()
      #expect(try scroll() === native)
      #expect(try button("Toggle long content").press())
      try await settle()
      #expect(abs(extent(try frame("Fill content")) - 900) < 1)
      #expect(abs(extent(native.documentView!.frame) - 1020) < 1)
      let start = native.contentView.bounds.origin
      native.contentView.scroll(
        to: horizontal ? CGPoint(x: start.x + (rtl ? -200 : 200), y: 0) : CGPoint(x: 0, y: 200))
      native.reflectScrolledClipView(native.contentView)
      try await settle()
      let scrolled = native.contentView.bounds.origin
      #expect(
        abs((horizontal ? scrolled.x - start.x : scrolled.y) - (horizontal && rtl ? -200 : 200)) < 1
      )
      #expect(try button("Toggle filling").press())
      try await settle()
      #expect(try scroll() === native)
      #expect(abs(extent(native.documentView!.frame) - 1020) < 1)
      #expect(
        abs(
          (horizontal
            ? native.contentView.bounds.minX - scrolled.x
            : native.contentView.bounds.minY - scrolled.y)) < 1)
      #expect(try button("Toggle long content").press())
      try await settle()
      #expect(abs(extent(try frame("Fill content")) - (horizontal ? 120 : 60)) < 1)
      #expect(try button("Toggle filling").press())
      try await settle()
      try checkShort()
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
