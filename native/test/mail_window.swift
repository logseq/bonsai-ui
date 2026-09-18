import AppKit
import SwiftUI

@testable import BonsaiSwiftUI

@main struct MailWindowAcceptance: App {
  @State private var session = BonsaiSession()
  init() {
    NSApplication.shared.appearance = NSAppearance(
      named: ProcessInfo.processInfo.environment["BONSAI_MAIL_HOST_APPEARANCE"] == "dark"
        ? .darkAqua : .aqua)
  }
  var body: some Scene {
    Window("Bonsai Mail", id: "mail-acceptance") {
      BonsaiApplicationView(entrypoint: "mail-collection", session: session)
        .frame(minWidth: 900, minHeight: 500)
        .task { await verifyMail(session) }
    }
    .defaultSize(width: 1200, height: 760)
  }
}

@MainActor private func verifyMail(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let content = window.contentView
    else { throw failure("Missing Mail window") }
    window.setContentSize(NSSize(width: 1200, height: 760))
    try await waitFor("Mara Vale", window: window)
    guard session.displayedRevision > 0 else {
      throw failure("Mail has not acknowledged presentation")
    }
    try await waitFor("Select a message", window: window)
    try requireLightAppearance(content)
    for mailbox in ["Inbox", "Starred", "Archived", "Trash", "Settings"] {
      _ = try button(mailbox, window: window)
    }
    func setMailColumnWidth(_ width: CGFloat) throws {
      func splits(_ view: NSView) -> [NSSplitView] {
        (view as? NSSplitView).map { [$0] + view.subviews.flatMap(splits) }
          ?? view.subviews.flatMap(splits)
      }
      guard
        let split = splits(content).first(where: { $0.isVertical && $0.arrangedSubviews.count == 3 }
        )
      else { throw failure("Missing native three-column Mail split view") }
      split.setPosition(
        split.arrangedSubviews[0].frame.maxX + split.dividerThickness + width, ofDividerAt: 1)
    }
    try setMailColumnWidth(560)
    for _ in 0..<4 { try await settleAccessibility(content) }
    let list = try mailList(content)
    guard list.bounds.width >= 340,
      let owner = session.tree.listNodes.first,
      let retainedRow = owner.children.flatMap({ Array($0.children.dropFirst(2)) }).first
    else { throw failure("Missing intrinsically sized native Mail List") }
    func firstRow() throws -> Int {
      try require(
        (0..<list.numberOfRows).first { row in
          guard let cell = list.view(atColumn: 0, row: row, makeIfNecessary: false) else {
            return false
          }
          return accessibilityElements(cell).contains { $0.label?.contains("Mara Vale") ?? false }
        })
    }
    let compact = list.rect(ofRow: try firstRow()).height
    try capture(window, state: "inbox", revision: session.displayedRevision)
    window.makeKeyAndOrderFront(nil)
    let element = try button("Unread message from Mara Vale", window: window)
    guard element.press() else { throw failure("Mail row did not accept expansion") }
    try await waitFor("Reply", window: window)
    try await settleAccessibility(content)
    for _ in 0..<4 { try await settleAccessibility(content) }
    let expanded = list.rect(ofRow: try firstRow()).height
    guard expanded > compact else { throw failure("Expanded Mail row did not grow") }
    let previousWidth = list.bounds.width
    try setMailColumnWidth(340)
    for _ in 0..<4 { try await settleAccessibility(content) }
    guard list.bounds.width < previousWidth,
      list.rect(ofRow: try firstRow()).height >= expanded,
      session.tree.nodes[retainedRow.id.node] === retainedRow
    else { throw failure("Native Mail List lost intrinsic sizing or row identity on resize") }
    try capture(window, state: "expanded-narrow", revision: session.displayedRevision)
    try setMailColumnWidth(560)
    for _ in 0..<4 { try await settleAccessibility(content) }
    try capture(window, state: "expanded", revision: session.displayedRevision)
    guard try button("Collapse message from Mara Vale", window: window).press()
    else { throw failure("Mail collapse action was rejected") }
    for _ in 0..<4 { try await settleAccessibility(content) }
    guard abs(list.rect(ofRow: try firstRow()).height - compact) < 1
    else { throw failure("Collapsed Mail row retained its expanded measurement") }
    guard try button("Unread message from Mara Vale", window: window).press()
    else { throw failure("Mail re-expansion action was rejected") }
    for _ in 0..<4 { try await settleAccessibility(content) }

    let nativeRow = try firstRow()
    let table: NSTableView = list
    let systemActions =
      table.delegate?.tableView?(table, rowActionsForRow: nativeRow, edge: .leading) ?? []
    guard systemActions.map(\.title) == ["Archive", "Trash"] else {
      throw failure("Expanded row lost its native swipe action identity")
    }
    let swipe = try require(retainedRow.children[1].swipeController)
    let archive = try require(swipe.actions.first)
    guard case .swipeAction(let properties) = archive.properties,
      properties.title == "Archive",
      swipe.perform(archive, expected: properties, generation: swipe.generation)
    else { throw failure("Archive command was not admitted") }
    for _ in 0..<100 {
      try await settleAccessibility(content)
      if !mailElements(window).contains(where: { $0.label?.contains("Mara Vale") ?? false }
      ) {
        break
      }
    }
    guard
      !mailElements(window).contains(where: { $0.label?.contains("Mara Vale") ?? false })
    else { throw failure("Archived message remained in the inbox") }
    guard try button("Archived", window: window).press() else {
      throw failure("Archived mailbox did not accept selection")
    }
    try await waitFor("Mara Vale", window: window)
    try requireLightAppearance(content)
    try capture(window, state: "archived", revision: session.displayedRevision)
    guard try button("Inbox", window: window).press() else {
      throw failure("Inbox mailbox did not accept selection")
    }
    try await waitFor("Inbox", window: window)
    try await settleAccessibility(content)
    guard
      !mailElements(window).contains(where: { $0.label?.contains("Mara Vale") ?? false })
    else { throw failure("Archived message reappeared when returning to the inbox") }
    let pagingList = try mailList(content)
    let initialRows = pagingList.numberOfRows
    for _ in 0..<100 {
      pagingList.scrollRowToVisible(max(0, pagingList.numberOfRows - 1))
      try await settleAccessibility(content)
      if pagingList.numberOfRows > initialRows + 1 { break }
    }
    guard pagingList.numberOfRows > initialRows + 1 else {
      throw failure("System List visibility did not load the next Mail page")
    }
    print(
      "PASS: actual Mail native window keeps its light palette and native appearance consistent, renders sidebar/inbox/detail, expands a card, and switches mailboxes after checking system row actions and dispatching Archive through OCaml"
    )
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
@MainActor private func mailList(_ content: NSView) throws -> NSOutlineView {
  func outlines(_ view: NSView) -> [NSOutlineView] {
    (view as? NSOutlineView).map { [$0] } ?? view.subviews.flatMap(outlines)
  }
  return try require(outlines(content).max(by: { $0.numberOfRows < $1.numberOfRows }))
}
private func require<T>(_ value: T?) throws -> T {
  guard let value else { throw failure("Missing native Mail object") }
  return value
}
@MainActor private func mailElements(_ window: NSWindow) -> [AccessibilityElement] {
  var elements = accessibilityElements(window)
  if let content = window.contentView, let list = try? mailList(content) {
    for row in 0..<list.numberOfRows {
      if let cell = list.view(atColumn: 0, row: row, makeIfNecessary: false) {
        elements += accessibilityElements(cell)
      }
    }
  }
  var seen = Set<ObjectIdentifier>()
  return elements.filter { seen.insert(ObjectIdentifier($0.object)).inserted }
}
@MainActor private func requireLightAppearance(_ content: NSView) throws {
  guard content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua else {
    throw failure("Mail's fixed light palette inherited a dark native appearance")
  }
}
@MainActor private func waitFor(_ text: String, window: NSWindow) async throws {
  for _ in 0..<100 {
    if let content = window.contentView { try await settleAccessibility(content) }
    if mailElements(window).contains(where: {
      ($0.value?.contains(text) ?? false) || ($0.label?.contains(text) ?? false)
    }) {
      return
    }
  }
  let values = mailElements(window).compactMap { $0.value ?? $0.label }
  throw failure("Missing \(text): \(values)")
}
@MainActor private func button(_ id: String, window: NSWindow) throws -> AccessibilityElement {
  let elements = mailElements(window)
  if let result = elements.first(where: {
    ($0.label?.contains(id) ?? false) && $0.role == "AXButton"
  }) {
    return result
  }
  if let identified = elements.first(where: { $0.identifier == id }),
    let result = accessibilityElements(identified.object).first(where: { $0.role == "AXButton" })
  {
    return result
  }
  throw failure(
    "Missing button \(id): \(elements.map { [$0.role, $0.label, $0.value].compactMap { $0 }.joined(separator: ": ") })"
  )
}
@MainActor private func capture(_ window: NSWindow, state: String, revision: UInt64) throws {
  guard let directory = ProcessInfo.processInfo.environment["BONSAI_MAIL_CAPTURE_DIRECTORY"] else {
    return
  }
  guard let view = window.contentView else { throw failure("Missing content view") }
  view.layoutSubtreeIfNeeded()
  view.displayIfNeeded()
  guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
    throw failure("Cannot allocate window bitmap")
  }
  view.cacheDisplay(in: view.bounds, to: bitmap)
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw failure("Cannot encode PNG")
  }
  let folder = URL(fileURLWithPath: directory)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  try png.write(to: folder.appendingPathComponent("mail-macos-\(state).png"))
  let manifest: [String: Any] = [
    "application": "Bonsai Mail", "entrypoint": "mail-collection", "model": "Mail.app",
    "capture":
      "NSView.cacheDisplay of a running standalone SwiftUI App window; not a desktop screenshot",
    "state": state, "revision": revision, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh,
    "contentWidthPoints": view.bounds.width, "contentHeightPoints": view.bounds.height,
    "displayScale": window.backingScaleFactor,
    "effectiveAppearance": view.effectiveAppearance.name.rawValue,
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "timestamp": ISO8601DateFormatter().string(from: Date()),
  ]
  try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: folder.appendingPathComponent("mail-macos-\(state).json"))
}
private func failure(_ message: String) -> NSError {
  NSError(domain: "MailWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
