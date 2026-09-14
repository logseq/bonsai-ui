import AppKit
import SwiftUI

@main struct NavigationWindowTest: App {
  private let appBarsMode = CommandLine.arguments.contains("--app-bars")
  private let toolbarMode = CommandLine.arguments.contains("--toolbar")
  private let tabsMode = CommandLine.arguments.contains("--tabs")
  private let twoColumnMode = CommandLine.arguments.contains("--split-two-columns")
  private var splitMode: Bool {
    twoColumnMode || CommandLine.arguments.contains("--split")
  }
  var body: some Scene {
    Window(
      "Navigation Acceptance",
      id: appBarsMode
        ? "app-bars-acceptance"
        : toolbarMode
          ? "toolbar-acceptance"
          : twoColumnMode
            ? "split-two-acceptance"
            : tabsMode
              ? "tabs-acceptance" : splitMode ? "split-acceptance" : "navigation-acceptance"
    ) {
      BonsaiApplicationView(
        entrypoint: appBarsMode
          ? "native-app-bars"
          : toolbarMode
            ? "native-toolbar"
            : twoColumnMode
              ? "native-split-two-columns"
              : tabsMode ? "native-tabs" : splitMode ? "native-split" : "native-navigation"
      )
      .frame(minWidth: splitMode ? 900 : 420, minHeight: splitMode ? 400 : 300)
      .task {
        if appBarsMode {
          await verifyAppBarsWindow()
        } else if toolbarMode {
          await verifyToolbarWindow()
        } else if tabsMode {
          await verifyTabsWindow()
        } else if splitMode {
          await verifySplitWindow(twoColumns: twoColumnMode)
        } else {
          await verifyNavigationWindow()
        }
      }
    }
    .defaultSize(width: splitMode ? 1200 : 520, height: splitMode ? 600 : 400)
  }
}

@MainActor private func waitForButton(_ label: String, in window: NSWindow, toolbar: Bool = false)
  async throws -> AccessibilityElement
{
  for _ in 0..<100 {
    if let content = window.contentView { try await settleAccessibility(content) }
    let elements =
      toolbar
      ? (window.toolbar?.items.compactMap(\.view).flatMap { accessibilityElements($0) } ?? [])
      : accessibilityElements(window)
    if let element = elements.first(where: {
      $0.role == "AXButton" && $0.enabled && ($0.label == label || $0.help == label)
    }) {
      return element
    }
  }
  let elements = accessibilityElements(window).map {
    "\($0.role ?? "-") \($0.label ?? "-") \($0.help ?? "-")"
  }
  throw NSError(
    domain: "NavigationWindowTest", code: 1,
    userInfo: [NSLocalizedDescriptionKey: "Missing \(label): \(elements)"])
}

@MainActor private func verifyNavigationWindow() async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
      throw NSError(domain: "NavigationWindowTest", code: 2)
    }
    let open = try await waitForButton("Open details", in: window)
    guard open.press() else { throw NSError(domain: "NavigationWindowTest", code: 3) }
    _ = try await waitForButton("Close details", in: window)
    let back = try await waitForButton("Back", in: window, toolbar: true)
    guard back.press() else { throw NSError(domain: "NavigationWindowTest", code: 4) }
    _ = try await waitForButton("Open details", in: window)
    print("PASS: actual SwiftUI NavigationStack system Back returns through OCaml")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}

@MainActor private func waitForText(_ text: String, in window: NSWindow) async throws {
  for _ in 0..<100 {
    if let content = window.contentView { try await settleAccessibility(content) }
    if accessibilityElements(window).contains(where: { $0.value == text || $0.label == text }) {
      return
    }
  }
  throw NSError(
    domain: "NavigationWindowTest", code: 5,
    userInfo: [
      NSLocalizedDescriptionKey:
        "Missing text: \(text); frame: \(window.frame); content: \(accessibilityElements(window).compactMap { $0.value ?? $0.label })"
    ])
}

@MainActor private func activateSidebar(in window: NSWindow) throws {
  let items = window.toolbar?.items ?? []
  guard
    let item = items.first(where: {
      $0.itemIdentifier == .toggleSidebar || $0.label.contains("Sidebar")
    })
  else {
    throw NSError(
      domain: "NavigationWindowTest", code: 6,
      userInfo: [
        NSLocalizedDescriptionKey:
          "Missing sidebar: \(items.map {($0.itemIdentifier.rawValue,$0.label)})"
      ])
  }
  let accepted: Bool
  if let view = item.view {
    let buttons = accessibilityElements(view).filter { $0.role == "AXButton" && $0.enabled }
    accepted = buttons.first?.press() ?? false
  } else if let action = item.action {
    accepted = NSApp.sendAction(action, to: item.target, from: item)
  } else {
    accepted = false
  }
  guard accepted else {
    throw NSError(
      domain: "NavigationWindowTest", code: 7,
      userInfo: [
        NSLocalizedDescriptionKey:
          "Sidebar control was not activated: \(item.label), \(item.view as Any), \(item.action as Any)"
      ])
  }
}

@MainActor private func verifySplitColumns(in window: NSWindow, count: Int, sidebarCollapsed: Bool)
  async throws
{
  func splits(_ view: NSView) -> [NSSplitView] {
    (view as? NSSplitView).map { [$0] } ?? view.subviews.flatMap(splits)
  }
  var measured = "No split view"
  for _ in 0..<20 {
    if let content = window.contentView {
      try await settleAccessibility(content)
      if let split = splits(content).first,
        let controller = split.delegate as? NSSplitViewController,
        let sidebar = controller.splitViewItems.first,
        split.arrangedSubviews.count == count, controller.splitViewItems.count == count
      {
        // Automatic SwiftUI styling may overlay a visible sidebar. Its native
        // split item, rather than adjacent column origins, owns collapse state.
        if sidebar.isCollapsed == sidebarCollapsed { return }
        measured = "collapsed=\(sidebar.isCollapsed), columns=\(controller.splitViewItems.count)"
      }
    }
  }
  throw NSError(
    domain: "NavigationWindowTest", code: 9,
    userInfo: [
      NSLocalizedDescriptionKey:
        "Expected \(count) columns, collapsed=\(sidebarCollapsed); \(measured)"
    ])
}

@MainActor private func verifySplitWindow(twoColumns: Bool) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
      throw NSError(domain: "NavigationWindowTest", code: 2)
    }
    // Window restoration must not turn the wide-column acceptance scenario
    // into a compact one after a previous application test used a small window.
    window.setContentSize(NSSize(width: 1200, height: 600))
    try await waitForText("Sidebar visible", in: window)
    let select = try await waitForButton("Select message", in: window)
    guard select.press() else { throw NSError(domain: "NavigationWindowTest", code: 3) }
    try await waitForText("Selected message", in: window)
    try await verifySplitColumns(in: window, count: twoColumns ? 2 : 3, sidebarCollapsed: false)
    for _ in 0..<3 {
      try activateSidebar(in: window)
      try await waitForText("Sidebar hidden", in: window)
      try await verifySplitColumns(in: window, count: twoColumns ? 2 : 3, sidebarCollapsed: true)
      try activateSidebar(in: window)
      try await waitForText("Sidebar visible", in: window)
      try await verifySplitColumns(in: window, count: twoColumns ? 2 : 3, sidebarCollapsed: false)
    }
    _ = try await waitForButton("Select message", in: window)
    try await waitForText("Selected message", in: window)
    window.setContentSize(NSSize(width: 1000, height: 450))
    try await waitForText("Selected message", in: window)
    print("PASS: actual Gallery system sidebar changes reach OCaml and retain selection")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}

@MainActor private func selectTab(_ label: String, in window: NSWindow) async throws {
  for _ in 0..<50 {
    if let content = window.contentView { try await settleAccessibility(content) }
    let elements =
      accessibilityElements(window)
      + (window.toolbar?.items.compactMap(\.view).flatMap { accessibilityElements($0) } ?? [])
    if let tab = elements.first(where: {
      ($0.role == "AXRadioButton" || $0.role == "AXButton")
        && ($0.label == label || $0.help == label) && $0.enabled
    }) {
      // Some SwiftUI radio elements perform the action but return false. The
      // caller verifies the resulting OCaml state instead of trusting that flag.
      _ = tab.press()
      if let content = window.contentView { try await settleAccessibility(content) }
      return
    }
  }
  let elements =
    accessibilityElements(window)
    + (window.toolbar?.items.compactMap(\.view).flatMap { accessibilityElements($0) } ?? [])
  throw NSError(
    domain: "NavigationWindowTest", code: 8,
    userInfo: [
      NSLocalizedDescriptionKey:
        "Missing tab \(label): \(elements.map { ($0.role, $0.label, $0.help) })"
    ])
}

@MainActor private func verifyTabsWindow() async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
      throw NSError(domain: "NavigationWindowTest", code: 2)
    }
    try await waitForText("Mail count: 0", in: window)
    let increment = try await waitForButton("Increment mail", in: window)
    guard increment.press() else { throw NSError(domain: "NavigationWindowTest", code: 3) }
    try await waitForText("Mail count: 1", in: window)
    try await selectTab("Chat", in: window)
    try await waitForText("Selected tab: chat", in: window)
    let lock = try await waitForButton("Lock tabs", in: window)
    guard lock.press() else { throw NSError(domain: "NavigationWindowTest", code: 3) }
    _ = try await waitForButton("Unlock tabs", in: window)
    try await selectTab("Mail", in: window)
    try await waitForText("Selected tab: chat", in: window)
    let unlock = try await waitForButton("Unlock tabs", in: window)
    guard unlock.press() else { throw NSError(domain: "NavigationWindowTest", code: 3) }
    _ = try await waitForButton("Lock tabs", in: window)
    try await selectTab("Mail", in: window)
    try await waitForText("Selected tab: mail", in: window)
    try await waitForText("Mail count: 1", in: window)
    let reorder = try await waitForButton("Reorder tabs", in: window)
    guard reorder.press() else { throw NSError(domain: "NavigationWindowTest", code: 3) }
    try await waitForText("Tab order: reversed", in: window)
    try await waitForText("Mail count: 1", in: window)
    let metadata = try await waitForButton("Update tab metadata", in: window)
    for phase in 1...4 {
      guard metadata.press() else { throw NSError(domain: "NavigationWindowTest", code: 3) }
      try await waitForText("Tab metadata: \(phase % 4)", in: window)
      try await selectTab("Chat", in: window)
      try await waitForText("Selected tab: chat", in: window)
      try await selectTab(phase == 4 ? "Mail" : "Inbox messages", in: window)
      try await waitForText("Selected tab: mail", in: window)
      try await waitForText("Mail count: 1", in: window)
    }
    print("PASS: actual Gallery system tabs preserve state, reject selection and reorder")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}

@MainActor private func verifyToolbarWindow() async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
      throw NSError(domain: "ToolbarWindowTest", code: 1)
    }
    window.setContentSize(NSSize(width: 1000, height: 600))
    try await waitForText("Toolbar actions: 0", in: window)
    let toolbarControls =
      window.toolbar?.items.compactMap(\.view).flatMap { accessibilityElements($0) } ?? []
    guard
      let pin = toolbarControls.first(where: {
        $0.label == "Pin toolbar" && $0.enabled
          && ($0.role == "AXCheckBox" || $0.role == "AXButton")
      })
    else {
      throw NSError(
        domain: "ToolbarWindowTest", code: 4,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Missing native toolbar toggle: \(toolbarControls.map { ($0.role, $0.label) })"
        ])
    }
    _ = pin.press()
    try await waitForText("Toolbar pinned", in: window)
    _ = pin.press()
    try await waitForText("Toolbar unpinned", in: window)
    for count in 1...2 {
      let action = try await waitForButton("Toolbar action", in: window, toolbar: true)
      _ = action.press()
      try await waitForText("Toolbar actions: \(count)", in: window)
    }
    let reverse = try await waitForButton("Reverse toolbar", in: window)
    _ = reverse.press()
    try await waitForText("Toolbar order: reversed", in: window)
    let action = try await waitForButton("Toolbar action", in: window, toolbar: true)
    _ = action.press()
    try await waitForText("Toolbar actions: 3", in: window)
    _ = try await waitForButton("Disable toolbar action", in: window).press()
    _ = try await waitForButton("Enable toolbar action", in: window)
    let entries =
      window.toolbar?.items.compactMap(\.view).flatMap { accessibilityElements($0) } ?? []
    guard entries.contains(where: { $0.label == "Toolbar action" && !$0.enabled }) else {
      throw NSError(
        domain: "ToolbarWindowTest", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Toolbar action did not become disabled"])
    }
    _ = try await waitForButton("Enable toolbar action", in: window).press()
    _ = try await waitForButton("Hide toolbar", in: window).press()
    _ = try await waitForButton("Show toolbar", in: window)
    if let content = window.contentView { try await settleAccessibility(content) }
    let hidden =
      window.toolbar?.items.compactMap(\.view).flatMap { accessibilityElements($0) } ?? []
    guard !hidden.contains(where: { $0.label == "Toolbar action" }) else {
      throw NSError(domain: "ToolbarWindowTest", code: 3)
    }
    _ = action.press()
    try await waitForText("Toolbar actions: 3", in: window)
    _ = try await waitForButton("Show toolbar", in: window).press()
    _ = try await waitForButton("Toolbar action", in: window, toolbar: true).press()
    try await waitForText("Toolbar actions: 4", in: window)
    window.setContentSize(NSSize(width: 520, height: 450))
    try await waitForText("Toolbar actions: 4", in: window)
    print("PASS: actual Gallery native toolbar commands reach OCaml and respect removal")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}

@MainActor private func verifyAppBarsWindow() async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
      throw NSError(domain: "AppBarsWindowTest", code: 1)
    }
    window.setContentSize(NSSize(width: 1000, height: 600))
    func scroll() throws -> NSScrollView {
      var pending = window.contentView.map { [$0] } ?? []
      while let view = pending.popLast() {
        if let scroll = view as? NSScrollView, !scroll.isHiddenOrHasHiddenAncestor,
          scroll.documentView != nil, scroll.contentView.bounds.height > 100
        {
          return scroll
        }
        pending.append(contentsOf: view.subviews)
      }
      throw NSError(domain: "AppBarsWindowTest", code: 2)
    }
    func require(_ value: Bool, _ message: String) throws {
      guard value else {
        throw NSError(
          domain: "AppBarsWindowTest", code: 3,
          userInfo: [NSLocalizedDescriptionKey: message])
      }
    }
    func rect(_ label: String) async throws -> CGRect {
      let element = try await waitForButton(label, in: window)
      let selector = NSSelectorFromString("accessibilityFrame")
      try require(element.object.responds(to: selector), "Missing native control frame")
      typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
      return unsafeBitCast(element.object.method(for: selector), to: Getter.self)(
        element.object, selector)
    }
    try await waitForText("Bar actions: 0", in: window)
    let viewport = try scroll()
    let originalSize = viewport.contentView.bounds.size
    try require(
      originalSize.height > 200 && originalSize.height < 600, "Unbounded navigation root scroll")
    let bottomBefore = try await rect("Bottom action")
    _ = try await waitForButton("Top action", in: window, toolbar: true).press()
    _ = try await waitForButton("Leading action", in: window, toolbar: true).press()
    _ = try await waitForButton("Bottom action", in: window).press()
    _ = try await waitForButton("Compose action", in: window).press()
    try await waitForText("Bar actions: 4", in: window)
    viewport.contentView.scroll(to: CGPoint(x: 0, y: 400))
    viewport.reflectScrolledClipView(viewport.contentView)
    try await waitForText("Bar actions: 4", in: window)
    try require(abs(viewport.documentVisibleRect.minY - 400) < 1, "Root scroll did not move")
    let bottomAfter = try await rect("Bottom action")
    try require(
      abs(bottomBefore.minY - bottomAfter.minY) < 1, "Bottom actions scrolled with content")
    _ = try await waitForButton("Resize bottom content", in: window).press()
    try await waitForText("Bottom height: 100", in: window)
    try require(
      abs(originalSize.height - viewport.contentView.bounds.height - 40) < 1,
      "Bottom content did not reduce the scroll viewport")
    try require(
      abs(viewport.documentVisibleRect.minY - 400) < 1, "Bottom resize lost scroll position")
    window.setContentSize(NSSize(width: 1100, height: 700))
    try await waitForText("Bottom height: 100", in: window)
    try require(
      abs(viewport.contentView.bounds.width - originalSize.width - 100) < 1,
      "Navigation body did not track window width")
    _ = try await waitForButton("Open bar details", in: window, toolbar: true).press()
    let detailAction = try await waitForButton("Detail action", in: window, toolbar: true)
    let activeToolbar =
      window.toolbar?.items.compactMap(\.view).flatMap { accessibilityElements($0) } ?? []
    try require(
      !activeToolbar.contains { $0.label == "Top action" && $0.enabled },
      "Root toolbar commands leaked into the destination")
    _ = detailAction.press()
    try await waitForText("Bar actions: 5", in: window)
    _ = try await waitForButton("Close bar details", in: window)
    let detailScroll = try scroll()
    try require(detailScroll.contentView.bounds.height < 700, "Unbounded destination scroll")
    _ = try await waitForButton("Back", in: window, toolbar: true).press()
    _ = try await waitForButton("Top action", in: window, toolbar: true)
    try await waitForText("Bottom height: 100", in: window)
    try require(
      abs(try scroll().documentVisibleRect.minY - 400) < 1, "System Back lost root scroll position")
    _ = try await waitForButton("Bottom action", in: window).press()
    try await waitForText("Bar actions: 6", in: window)
    print("PASS: actual Gallery app bars use native toolbar and bounded navigation pages")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
