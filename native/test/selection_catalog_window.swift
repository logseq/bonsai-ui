import AppKit
import SwiftUI

@main struct SelectionCatalogWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Selection Catalog Acceptance", id: "selection-catalog-acceptance") {
      BonsaiApplicationView(entrypoint: "native-selection-catalog", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 760)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 800)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing selection catalog window") }
    func contains(_ title: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let value) = $0.properties { return value.value == title }
        return false
      }
    }
    func wait(_ condition: () -> Bool) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil && condition() { return }
      }
      throw failure("Selection catalog state did not settle")
    }
    func press(_ title: String) throws {
      guard
        let control = accessibilityElements(host).first(where: {
          $0.label == title && $0.enabled
            && ["AXButton", "AXCheckBox", "AXRadioButton"].contains($0.role)
        })
      else { throw failure("Cannot find enabled control \(title)") }
      // AppKit segmented accessibility can return false after dispatching the action.
      // The subsequent OCaml-state assertion is the evidence of activation.
      _ = control.press()
    }
    func edit(_ text: String) throws {
      guard let field = session.tree.nodes.values.compactMap(\.fieldController).first?.field else {
        throw failure("Missing search field")
      }
      field.selectText(nil)
      guard let editor = field.currentEditor() as? NSTextView else {
        throw failure("Missing native field editor")
      }
      editor.insertText(
        text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    }
    func menu(_ title: String) throws -> NSMenu {
      var views = [host]
      while let view = views.popLast() {
        if let popup = view as? NSPopUpButton, popup.title == title, let menu = popup.menu {
          let timer = Timer(timeInterval: 0.1, repeats: false) { _ in
            MainActor.assumeIsolated { menu.cancelTracking() }
          }
          RunLoop.main.add(timer, forMode: .common)
          popup.performClick(nil)
          timer.invalidate()
          return menu
        }
        views.append(contentsOf: view.subviews)
      }
      throw failure("Missing native menu \(title)")
    }
    func select(_ title: String, in menu: NSMenu) throws {
      guard let index = menu.items.firstIndex(where: { $0.title == title }),
        menu.items[index].isEnabled, menu.items[index].action != nil
      else { throw failure("Missing enabled menu action \(title)") }
      menu.performActionForItem(at: index)
    }
    try await wait { contains("Selected single: Inbox") && session.displayedRevision > 0 }
    try press("Single Archive")
    try await wait { contains("Selected single: Archive") }
    try press("Multiple Archive")
    try await wait { contains("Selected multiple: Inbox, Archive") }
    try press("Open Inbox")
    try press("Open Inbox")
    try await wait { contains("Actions: 2 (Inbox)") }
    try edit("Inbox")
    try await wait {
      contains("Selected single: Archive") && !contains("Single Archive")
        && session.tree.nodes.values.compactMap(\.pickerController).first?.selection == nil
    }
    try edit("no results")
    try await wait { contains("No matching choices") }
    try press("Show error")
    try await wait { contains("Choices could not be loaded") }
    try press("Retry choices")
    try await wait { contains("No matching choices") }
    try edit("")
    try await wait {
      contains("Single Archive")
        && session.tree.nodes.values.compactMap(\.pickerController).first?.selection == 9
    }
    try press("Use menus")
    try await wait { contains("Multiple choices") }
    window.setContentSize(CGSize(width: 360, height: 800))
    try await settleAccessibility(host)
    guard abs(host.bounds.width - 360) < 1 else {
      throw failure("Menu composition does not fit a 360-point window")
    }
    let choices = try menu("Multiple choices")
    guard choices.items.first(where: { $0.title == "Multiple Archive" })?.state == .on,
      choices.items.first(where: { $0.title == "Multiple Unavailable" })?.isEnabled == false
    else { throw failure("Native menu lost canonical selection or disabled state") }
    try select("Multiple Archive", in: choices)
    try await wait { contains("Selected multiple: Inbox") }
    try press("Ignore selection changes")
    try await wait { contains("Accept selection changes") }
    try select("Multiple Archive", in: menu("Multiple choices"))
    try await wait {
      session.tree.nodes.values.compactMap(\.menuController).allSatisfy { $0.pending.isEmpty }
    }
    guard
      try menu("Multiple choices").items.first(where: { $0.title == "Multiple Archive" })?.state
        == .off
    else {
      throw failure("Rejected menu selection was not restored")
    }
    await session.close()
    print(
      "PASS: actual Gallery selection catalog native search, choices, repeated actions and menus preserve OCaml state at desktop and compact widths"
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
  NSError(
    domain: "SelectionCatalogWindowAcceptance", code: 1,
    userInfo: [NSLocalizedDescriptionKey: message])
}
