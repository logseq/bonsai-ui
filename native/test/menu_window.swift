import AppKit
import SwiftUI

@main struct MenuWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Menu Acceptance", id: "menu-acceptance") {
      BonsaiApplicationView(entrypoint: "native-menu", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 320)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 400)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing menu window") }
    func controller() -> NativeMenuController? {
      session.tree.nodes.values.compactMap(\.menuController).first
    }
    func wait(_ condition: () -> Bool) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil && condition() { return }
      }
      throw failure("Menu state did not settle")
    }
    func button(_ name: String) throws {
      guard
        let button = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == name && $0.enabled
        }), button.press()
      else { throw failure("Cannot press \(name)") }
    }
    func populatedMenu() throws -> NSMenu {
      var views = [host]
      var popup: NSPopUpButton?
      while let view = views.popLast() {
        if let value = view as? NSPopUpButton { popup = value }
        views.append(contentsOf: view.subviews)
      }
      guard let popup, let menu = popup.menu else { throw failure("Missing native menu button") }
      let closeMenu = Timer(timeInterval: 0.1, repeats: false) { _ in
        MainActor.assumeIsolated { menu.cancelTracking() }
      }
      RunLoop.main.add(closeMenu, forMode: .common)
      popup.performClick(nil)
      closeMenu.invalidate()
      return menu
    }
    func item(_ name: String, in menu: NSMenu) throws -> (NSMenu, NSMenuItem) {
      for entry in menu.items {
        if entry.title == name { return (menu, entry) }
        if let submenu = entry.submenu {
          submenu.delegate?.menuNeedsUpdate?(submenu)
          if let found = try? item(name, in: submenu) { return found }
        }
      }
      throw failure("Missing menu item \(name)")
    }
    func select(_ name: String, in menu: NSMenu) throws {
      let (owner, selected) = try item(name, in: menu)
      guard selected.isEnabled, selected.action != nil else {
        throw failure("Menu item \(name) has no enabled action")
      }
      owner.performActionForItem(at: owner.index(of: selected))
    }
    try await wait { controller() != nil && session.displayedRevision > 0 }
    for width in [640.0, 360.0] {
      window.setContentSize(CGSize(width: width, height: 400))
      try await settleAccessibility(host)
      let menu = try populatedMenu()
      guard !(try item("Disabled action", in: menu).1.isEnabled),
        !(try item("Unavailable child", in: menu).1.isEnabled),
        (try item("Export", in: menu).1.submenu) != nil
      else { throw failure("Missing hierarchy or disabled menu state") }
      guard (try item("Open", in: menu).1.image) != nil else {
        throw failure("Menu action lost its symbol")
      }
      try select("Open", in: menu)
      try await wait { controller()?.pending.isEmpty == true }
      guard
        session.tree.nodes.values.contains(where: {
          if case .text(let text) = $0.properties { return text.value.contains("-7") }
          return false
        })
      else { throw failure("Native menu action did not reach OCaml") }
      try select("PDF", in: try populatedMenu())
      try await wait { controller()?.pending.isEmpty == true }
      guard
        session.tree.nodes.values.contains(where: {
          if case .text(let text) = $0.properties { return text.value.contains("21") }
          return false
        })
      else { throw failure("Native submenu action did not reach OCaml") }
      let before = controller()?.checked(9)
      try select("Pinned", in: try populatedMenu())
      try await wait { controller()?.pending.isEmpty == true && controller()?.checked(9) != before }
      try button("Ignore menu changes")
      try await wait { accessibilityElements(host).contains { $0.label == "Accept menu changes" } }
      let retained = controller()?.checked(9)
      try select("Pinned", in: try populatedMenu())
      try await wait {
        controller()?.pending.isEmpty == true && controller()?.checked(9) == retained
      }
      let restored = try populatedMenu()
      guard (try item("Pinned", in: restored).1.state == .on) == retained else {
        throw failure("Rejected native checkmark was not restored")
      }
      try button("Accept menu changes")
      try await wait { accessibilityElements(host).contains { $0.label == "Ignore menu changes" } }
    }
    await session.close()
    print(
      "PASS: actual Gallery Menu native actions and controlled checks preserve hierarchy, disabling and rejection at both widths"
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

private func failure(_ message: String) -> NSError {
  NSError(domain: "MenuWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
