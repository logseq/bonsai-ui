import AppKit
import SwiftUI

@main struct CarouselWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Carousel Acceptance", id: "carousel-acceptance") {
      BonsaiApplicationView(entrypoint: "native-carousel", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 660)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 720)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else {
      throw failure("Missing Carousel window")
    }
    func contains(_ title: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == title }
        return false
      }
    }
    func controller() -> ScrollTargetsController? {
      session.tree.nodes.values.compactMap(\.scrollTargetsController).first
    }
    var stage = "initial"
    func wait(_ condition: () -> Bool) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil && condition() { return }
      }
      throw failure(
        "Carousel did not settle at \(stage): position=\(String(describing:controller()?.position)) pending=\(String(describing:controller()?.pending))"
      )
    }
    func press(_ title: String) throws {
      guard
        let button = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title && $0.enabled
        })
      else {
        throw failure("Missing enabled button \(title)")
      }
      _ = button.press()
    }
    func scroll() throws -> NSScrollView {
      var views = [host]
      while let view = views.popLast() {
        if let scroll = view as? NSScrollView { return scroll }
        views.append(contentsOf: view.subviews)
      }
      throw failure("Missing native ScrollView")
    }
    func moveViewport(vertical: Bool) async throws -> CGPoint {
      let target = try scroll()
      let before = target.contentView.bounds.origin
      let next =
        vertical
        ? CGPoint(x: before.x, y: before.y - 212 + 53)
        : CGPoint(x: before.x - 292 + 53, y: before.y)
      target.contentView.scroll(to: next)
      target.reflectScrolledClipView(target.contentView)
      try await settleAccessibility(host)
      return next
    }
    try await wait { controller()?.position == -7 && session.displayedRevision > 0 }
    try press("Disable snapping")
    try await wait { contains("Enable snapping") }
    for vertical in [false, true] {
      if vertical {
        try press("Use vertical layout")
        try await wait { contains("Axis: Vertical") }
      }
      try press("Go to last card")
      try await wait { controller()?.position == 13 && controller()?.pending == nil }
      stage = "scroll, vertical=\(vertical)"
      let requested = try await moveViewport(vertical: vertical)
      try await wait { controller()?.position == 9 && controller()?.pending == nil }
      let actual = try scroll().contentView.bounds.origin
      guard abs(actual.x - requested.x) < 1 && abs(actual.y - requested.y) < 1 else {
        throw failure(
          "Position reporting snapped a free viewport: requested \(requested), actual \(actual)")
      }
      guard !contains("Position updates: 0") else {
        throw failure("Native scroll never reached OCaml")
      }
      try press("Go to last card")
      try await wait { controller()?.position == 13 && controller()?.pending == nil }
      let origin = try scroll().contentView.bounds.origin
      stage = "rejection, vertical=\(vertical)"
      try press("Ignore scroll changes")
      try await wait { contains("Accept scroll changes") }
      _ = try await moveViewport(vertical: vertical)
      try await wait {
        guard let current = try? scroll().contentView.bounds.origin else { return false }
        return controller()?.position == 13 && controller()?.pending == nil
          && abs(current.x - origin.x) < 1 && abs(current.y - origin.y) < 1
      }
      try press("Accept scroll changes")
      try await wait { contains("Ignore scroll changes") }
      try press("Open third")
      try await wait { contains(vertical ? "Opened: 13 (2 actions)" : "Opened: 13 (1 actions)") }
    }
    await session.close()
    print(
      "PASS: actual Carousel native viewport changes update OCaml, preserve free scrolling and restore rejected positions on both axes"
    )
    fflush(stdout)
    exit(0)
  } catch {
    await session.close()
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func failure(_ text: String) -> NSError {
  NSError(domain: "CarouselWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
