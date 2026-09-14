import AppKit
import SwiftUI

@main struct MixedCollectionWindowAcceptance: App {
  @State private var session = BonsaiSession()
  private let horizontal = CommandLine.arguments.contains("--horizontal")
  private let rtl = CommandLine.arguments.contains("--rtl")
  var body: some Scene {
    Window("Mixed collection", id: "mixed-acceptance") {
      BonsaiApplicationView(
        entrypoint: horizontal ? "native-mixed-h" : "native-mixed-v", session: session
      )
      .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
      .frame(minWidth: 480, minHeight: 450)
      .task { await verify(session, horizontal: horizontal, rtl: rtl) }
    }
    .defaultSize(width: 820, height: 850)
  }
}

@MainActor private func verify(_ session: BonsaiSession, horizontal: Bool, rtl: Bool) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let content = window.contentView
    else { throw failure("Missing native window") }
    window.setContentSize(CGSize(width: 820, height: 850))
    func wait(_ predicate: () -> Bool) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(content)
        if predicate() { return }
      }
      throw failure("Application state did not settle")
    }
    func button(_ title: String) -> AccessibilityElement? {
      accessibilityElements(window).first { $0.role == "AXButton" && $0.label == title }
    }
    func press(_ title: String) throws {
      print("PRESS: \(title)")
      fflush(stdout)
      guard button(title)?.press() == true else { throw failure("Missing action: \(title)") }
    }
    try await wait { button("Header action") != nil }
    guard let controller = session.tree.nodes.values.compactMap(\.collectionController).first,
      let scroll = scrolls(content).first,
      let document = scroll.documentView,
      scrolls(content).count == 1
    else { throw failure("Expected one native collection") }
    let target = controller.catalog.geometry.offset(at: 7500) + 7
    let x = rtl ? document.frame.width - scroll.contentView.bounds.width - target : target
    scroll.contentView.scroll(to: horizontal ? CGPoint(x: x, y: 0) : CGPoint(x: 0, y: target))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await wait { controller.viewport.visibleRange.contains(7500) }
    try press("Clear mixed content")
    try await wait { controller.catalog.keys.isEmpty }
    try press("Reset mixed content")
    try await wait { controller.catalog.keys.count == 10003 && button("Header action") != nil }
    guard controller.viewport.visibleExtent > 300,
      abs(controller.viewport.leadingOffset) < 1,
      scrolls(content).first === scroll
    else { throw failure("Reset lost the bounded viewport or leading position") }
    try press("Header action")
    try await wait {
      accessibilityElements(window).contains { ($0.value ?? $0.label) == "Mixed actions: 1" }
    }
    print(
      "PASS: actual mixed collection window restores content; horizontal=\(horizontal) rtl=\(rtl)")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}

@MainActor private func scrolls(_ root: NSView) -> [NSScrollView] {
  (root as? NSScrollView).map { [$0] } ?? root.subviews.flatMap(scrolls)
}

private func failure(_ message: String) -> NSError {
  NSError(
    domain: "MixedCollectionWindowAcceptance", code: 1,
    userInfo: [NSLocalizedDescriptionKey: message])
}
