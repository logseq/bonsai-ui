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
    guard
      let viewport = session.tree.nodes.values.compactMap({ $0.collectionController?.viewport })
        .first,
      viewport.visibleRect.width >= 340
    else {
      throw failure(
        "Mail list is too narrow: \(session.tree.nodes.values.compactMap { $0.collectionController?.viewport.visibleRect.width })"
      )
    }
    guard
      let owner = session.tree.nodes.values.first(where: {
        $0.collectionController?.catalog.keys.count == 20
      }), let collection = owner.collectionController,
      collection.catalog.measurementRevision != nil,
      let retainedRow = owner.children.first?.children.first
    else { throw failure("Mail must use intrinsic measured collection rows") }
    let compact = collection.viewport.geometry.extent(at: 0)
    try capture(window, state: "inbox", revision: session.displayedRevision)
    window.makeKeyAndOrderFront(nil)
    try await verifyRowDrag(window, content: content)
    let element = try button("Unread message from Mara Vale", window: window)
    guard element.press() else { throw failure("Mail row did not accept expansion") }
    try await waitFor("Reply", window: window)
    try await settleAccessibility(content)
    for _ in 0..<4 { try await settleAccessibility(content) }
    let expanded = collection.viewport.geometry.extent(at: 0)
    guard expanded > compact else { throw failure("Expanded Mail row did not grow") }
    let previousWidth = collection.viewport.visibleRect.width
    try setMailColumnWidth(340)
    for _ in 0..<4 { try await settleAccessibility(content) }
    guard collection.viewport.visibleRect.width < previousWidth,
      collection.viewport.geometry.extent(at: 0) > expanded,
      collection.viewport.leadingOffset < 1,
      session.tree.nodes[retainedRow.id.node] === retainedRow
    else {
      throw failure(
        "Narrow Mail geometry: width \(previousWidth) -> \(collection.viewport.visibleRect.width), height \(expanded) -> \(collection.viewport.geometry.extent(at: 0)), offset \(collection.viewport.leadingOffset), retained \(session.tree.nodes[retainedRow.id.node] === retainedRow)"
      )
    }
    try capture(window, state: "expanded-narrow", revision: session.displayedRevision)
    try setMailColumnWidth(560)
    for _ in 0..<4 { try await settleAccessibility(content) }
    try capture(window, state: "expanded", revision: session.displayedRevision)
    guard try button("Collapse message from Mara Vale", window: window).press()
    else { throw failure("Mail collapse action was rejected") }
    for _ in 0..<4 { try await settleAccessibility(content) }
    guard abs(collection.viewport.geometry.extent(at: 0) - compact) < 1
    else { throw failure("Collapsed Mail row retained its expanded measurement") }
    guard try button("Unread message from Mara Vale", window: window).press()
    else { throw failure("Mail re-expansion action was rejected") }
    for _ in 0..<4 { try await settleAccessibility(content) }

    let row = accessibilityElements(window).first { element in
      element.actions.contains { $0.name == "Archive" }
        && accessibilityElements(element.object).contains {
          $0.label?.contains("Mara Vale") ?? false
        }
    }
    guard let archive = row?.actions.first(where: { $0.name == "Archive" }),
      archive.handler?() == true
    else { throw failure("Missing Mail row Archive action") }
    for _ in 0..<100 {
      try await settleAccessibility(content)
      if !accessibilityElements(window).contains(where: { $0.label?.contains("Mara Vale") ?? false }
      ) {
        break
      }
    }
    guard
      !accessibilityElements(window).contains(where: { $0.label?.contains("Mara Vale") ?? false })
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
      !accessibilityElements(window).contains(where: { $0.label?.contains("Mara Vale") ?? false })
    else { throw failure("Archived message reappeared when returning to the inbox") }
    print(
      "PASS: actual Mail native window keeps its light palette and native appearance consistent, renders sidebar/inbox/detail, expands a card, and switches mailboxes after archiving through OCaml"
    )
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
@MainActor private func verifyRowDrag(_ window: NSWindow, content: NSView) async throws {
  let row = try button("Unread message from Mara Vale", window: window)
  let selector = NSSelectorFromString("accessibilityFrame")
  guard row.object.responds(to: selector) else { throw failure("Missing Mail row frame") }
  typealias FrameGetter = @convention(c) (AnyObject, Selector) -> CGRect
  let getFrame = unsafeBitCast(row.object.method(for: selector), to: FrameGetter.self)
  let frame = getFrame(row.object, selector)
  guard frame.width >= 340, frame.height > 40 else {
    throw failure("Invalid Mail drag frame: \(frame)")
  }
  let start = CGPoint(x: frame.minX + frame.width * 0.25, y: frame.midY)
  let time = ProcessInfo.processInfo.systemUptime
  for step in 0...12 {
    let point = window.convertPoint(
      fromScreen: CGPoint(x: start.x + 150 * CGFloat(step) / 12, y: start.y))
    let type: NSEvent.EventType =
      step == 0 ? .leftMouseDown : step == 12 ? .leftMouseUp : .leftMouseDragged
    guard
      let event = NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [], timestamp: time + Double(step) * 0.016,
        windowNumber: window.windowNumber, context: nil, eventNumber: step, clickCount: 1,
        pressure: step == 12 ? 0 : 1)
    else { throw failure("Cannot create Mail drag event") }
    NSApp.postEvent(event, atStart: false)
  }
  for _ in 0..<4 { try await settleAccessibility(content) }
  let elements = accessibilityElements(window)
  let archives = elements.filter { $0.role == "AXButton" && $0.label == "Archive" }
  guard archives.count == 1, archives[0].enabled,
    !elements.contains(where: { $0.label == "Collapse message from Mara Vale" })
  else {
    throw failure(
      "Mail mouse drag must reveal one Archive without expanding the row: \(elements.compactMap { $0.label })"
    )
  }
  guard let close = elements.flatMap(\.actions).first(where: { $0.name == "Close actions" }),
    close.handler?() == true
  else { throw failure("Mail drag pane cannot be closed") }
  for _ in 0..<4 { try await settleAccessibility(content) }
  for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    guard
      let event = NSEvent.mouseEvent(
        with: type, location: window.convertPoint(fromScreen: start), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 20, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
    else { throw failure("Cannot create Mail click event") }
    NSApp.postEvent(event, atStart: false)
  }
  for _ in 0..<4 { try await settleAccessibility(content) }
  guard try button("Collapse message from Mara Vale", window: window).press() else {
    throw failure("Ordinary Mail mouse click stopped expanding the row")
  }
  for _ in 0..<4 { try await settleAccessibility(content) }
}
@MainActor private func requireLightAppearance(_ content: NSView) throws {
  guard content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua else {
    throw failure("Mail's fixed light palette inherited a dark native appearance")
  }
}
@MainActor private func waitFor(_ text: String, window: NSWindow) async throws {
  for _ in 0..<100 {
    if let content = window.contentView { try await settleAccessibility(content) }
    if accessibilityElements(window).contains(where: {
      ($0.value?.contains(text) ?? false) || ($0.label?.contains(text) ?? false)
    }) {
      return
    }
  }
  let values = accessibilityElements(window).compactMap { $0.value ?? $0.label }
  throw failure("Missing \(text): \(values)")
}
@MainActor private func button(_ id: String, window: NSWindow) throws -> AccessibilityElement {
  let elements = accessibilityElements(window)
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
