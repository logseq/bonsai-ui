import AppKit
import Observation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor @Observable private final class MenuSettings { var phase = ScenePhase.active }
@MainActor private struct MenuServiceHost: View {
  let session: BonsaiSession
  let settings: MenuSettings
  var body: some View {
    BonsaiApplicationView(entrypoint: "native-menu-service", session: session)
      .environment(\.scenePhase, settings.phase).allowsWindowActivationEvents(true)
  }
}
@MainActor private final class MenuServiceScene {
  let session: BonsaiSession
  let settings = MenuSettings()
  let window: NSWindow
  var host: NSView?
  private var events: BonsaiApplicationEvents?
  init(width: CGFloat = 640) {
    initializeAccessibilityApplication()
    window = NSWindow(
      contentRect: CGRect(x: 80, y: 80, width: width, height: 480),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    var connect: ((BonsaiApplicationEvents) -> Void)?
    session = BonsaiSession(
      applicationBridge: BonsaiApplicationBridge(request: { $0 }, connected: { connect?($0) }))
    connect = { [weak self] in self?.events = $0 }
  }
  func start() async throws {
    let hosting = NSHostingView(rootView: MenuServiceHost(session: session, settings: settings))
    hosting.sizingOptions = []
    host = hosting
    window.contentView = hosting
    window.orderFront(nil)
    try await wait { self.session.displayedRevision > 0 && self.events != nil }
    try await settleAccessibility(hosting)
  }
  var status: String {
    session.tree.nodes.values.compactMap {
      if case .text(let value) = $0.properties, value.value.hasPrefix("Menus:") {
        return value.value
      }
      return nil
    }.first ?? ""
  }
  func text(_ value: String) -> Bool {
    session.tree.nodes.values.contains {
      if case .text(let text) = $0.properties { return text.value == value }
      return false
    }
  }
  var sheet: NSWindow? { window.attachedSheet }
  var choices: [AccessibilityElement] {
    // Include native List cell hosts as accessibility roots, as well as the sheet.
    var views = sheet?.contentView.map { [$0] } ?? []
    var result: [AccessibilityElement] = []
    var visited = Set<ObjectIdentifier>()
    while let view = views.popLast() {
      views.append(contentsOf: view.subviews)
      result.append(
        contentsOf: accessibilityElements(view).filter {
          visited.insert(ObjectIdentifier($0.object)).inserted
        })
    }
    return result
  }
  func action(_ title: String) throws -> AccessibilityElement {
    try #require(
      choices.first { $0.role == "AXButton" && $0.label == title },
      "Missing \(title); choices=\(choices.compactMap(\.label)); \(status)")
  }
  func rootButton(_ title: String) throws -> AccessibilityElement {
    try #require(
      host.flatMap {
        accessibilityElements($0).first { $0.role == "AXButton" && $0.label == title }
      })
  }
  func send(_ command: String) throws { try #require(events).send(Data(command.utf8)) }
  func show(_ tag: String, mode: String = "regular") async throws {
    try send("show:\(tag):\(mode)")
    try await wait { self.sheet?.isVisible == true }
    try await settleAccessibility(#require(sheet?.contentView))

  }
  func tick() async throws {
    for view in [host, sheet?.contentView].compactMap({ $0 }) {
      view.layoutSubtreeIfNeeded()
      view.displayIfNeeded()
    }
    try await Task.sleep(for: .milliseconds(10))
  }
  func wait(_ condition: () -> Bool) async throws {
    for _ in 0..<250 {
      if condition() { return }
      try await tick()
    }
    try #require(
      condition(),
      "\(status); displayed=\(session.displayedRevision); sheet=\(String(describing: sheet)); choices=\(choices.compactMap(\.label))"
    )
  }
  func settle() async throws { for _ in 0..<12 { try await tick() } }
  func close() async {
    window.orderOut(nil)
    window.contentView = nil
    host = nil
    await session.close()
  }
  func scrollToLastChoice() throws {
    var views = [try #require(sheet?.contentView)]
    var scroll: NSScrollView?
    while let view = views.popLast() {
      if let candidate = view as? NSScrollView, let document = candidate.documentView,
        document.bounds.height > candidate.contentView.bounds.height
      {
        scroll = candidate
        break
      }
      views.append(contentsOf: view.subviews)
    }
    let owner = try #require(scroll)
    let document = try #require(owner.documentView)
    let y =
      document.isFlipped ? max(0, document.bounds.height - owner.contentView.bounds.height) : 0
    owner.contentView.scroll(to: CGPoint(x: 0, y: y))
    owner.reflectScrolledClipView(owner.contentView)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func hostMenusSelectActualOcamlAndBlockBackgroundAtBothWidths() async throws {
    for width in [640.0, 360.0] {
      let scene = MenuServiceScene(width: width)
      do {
        try await scene.start()
        let background = try scene.rootButton("Background action")
        try await scene.show("selected")
        #expect(try !scene.action("Unavailable action").enabled)
        _ = background.press()
        try await scene.settle()
        #expect(scene.text("Background: 0"))
        #expect(try #require(scene.sheet).frame.width <= scene.window.frame.width)
        let action = try scene.action("Save copy 😀")
        #expect(action.press())
        try await scene.wait { scene.status == "Menus:selected=保存😀;" && scene.sheet == nil }
        _ = action.press()
        try await scene.settle()
        #expect(scene.status == "Menus:selected=保存😀;")
        #expect(try scene.rootButton("Background action").press())
        try await scene.wait { scene.text("Background: 1") }
        await scene.close()
      } catch {
        await scene.close()
        throw error
      }
    }
  }

  @Test @MainActor func hostMenusDismissScrollAndRetainDisabledChoices() async throws {
    let scene = MenuServiceScene(width: 360)
    do {
      try await scene.start()
      try await scene.show("disabled", mode: "disabled")
      #expect(try !scene.action("Open document").enabled)
      #expect(try !scene.action("Save copy 😀").enabled)
      #expect(try scene.action("Cancel").press())
      try await scene.wait { scene.status.contains("disabled=dismissed;") && scene.sheet == nil }
      try await scene.show("large", mode: "large")
      try scene.scrollToLastChoice()
      try await scene.wait { scene.choices.contains { $0.label == "Action 128" } }
      #expect(try scene.action("Action 128").press())
      try await scene.wait { scene.status.contains("large=128;") && scene.sheet == nil }
      try await scene.show("unicode", mode: "unicode")
      #expect(try !scene.action("Composed ID").enabled)
      #expect(try scene.action("Decomposed ID").press())
      try await scene.wait { scene.status.contains("unicode=") && scene.sheet == nil }
      #expect(
        Data(scene.status.utf8).suffix(Data("unicode=e\u{301};".utf8).count)
          == Data("unicode=e\u{301};".utf8))
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func hostMenusCancelBusyRequestsAndFenceRestartedCallbacks() async throws {
    let scene = MenuServiceScene()
    do {
      try await scene.start()
      try await scene.show("first")
      let retired = try scene.action("Open document")
      try scene.send("show:second:regular")
      try await scene.wait { scene.status.contains("second=error;") }
      #expect(scene.sheet != nil)
      try scene.send("cancel:first")
      try await scene.wait { scene.status.contains("first=cancelled;") && scene.sheet == nil }
      try await scene.show("next")
      _ = retired.press()
      try await scene.settle()
      #expect(!scene.status.contains("next="))
      await scene.close()
      try await scene.start()
      try await scene.show("restart")
      _ = retired.press()
      #expect(try scene.action("Open document").press())
      try await scene.wait { scene.status == "Menus:restart=open;" && scene.sheet == nil }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func hostMenusAndFileDialogsCannotOverlap() async throws {
    let scene = MenuServiceScene()
    do {
      try await scene.start()
      try await scene.show("menu")
      let menu = try #require(scene.sheet)
      try scene.send("file:blockedFile")
      try await scene.wait { scene.status.contains("blockedFile=error;") }
      #expect(scene.sheet === menu)
      #expect(try scene.action("Cancel").press())
      try await scene.wait { scene.sheet == nil }
      try scene.send("file:picker")
      try await scene.wait { scene.sheet?.isVisible == true }
      let picker = try #require(scene.sheet)
      try scene.send("show:blockedMenu:regular")
      try await scene.wait { scene.status.contains("blockedMenu=error;") }
      #expect(scene.sheet === picker)
      try scene.send("cancel:picker")
      try await scene.wait { scene.sheet == nil && scene.status.contains("picker=cancelled;") }
      try await scene.show("afterFile")
      #expect(try scene.action("Open document").press())
      try await scene.wait { scene.status.contains("afterFile=open;") }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func hostMenusDeferInactiveRequestsAndCancelLostWindowContext() async throws {
    let scene = MenuServiceScene()
    do {
      try await scene.start()
      #expect(try scene.rootButton("Show action menu").press())
      scene.settings.phase = .background
      try await scene.wait { !scene.session.isActive }
      try await scene.settle()
      #expect(scene.sheet == nil)
      scene.settings.phase = .active
      try await scene.wait { scene.sheet?.isVisible == true && !scene.choices.isEmpty }
      scene.settings.phase = .background
      try await scene.wait { !scene.session.isActive && scene.sheet == nil }
      scene.settings.phase = .active
      try await scene.wait { scene.status.contains("button=cancelled;") }
      #expect(scene.sheet == nil)
      try await scene.show("hidden")
      scene.window.orderOut(nil)
      try await scene.wait { !scene.session.isVisible && scene.sheet == nil }
      scene.window.orderFront(nil)
      try await scene.wait { scene.status.contains("hidden=cancelled;") }
      try await scene.show("resumed")
      #expect(try scene.action("Cancel").press())
      try await scene.wait { scene.status.contains("resumed=dismissed;") }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }
}

struct HostMenuWireTests {
  private func bytes(_ items: [(String, String, UInt8)]) throws -> Data {
    var writer = WireWriter()
    writer.integer(UInt64(1))
    writer.integer(UInt16(11))
    writer.integer(UInt16(items.count))
    for (id, label, enabled) in items {
      try writer.string(id)
      try writer.string(label)
      writer.integer(enabled)
    }
    return writer.bytes
  }
  @Test func menusValidateTheirWholeChoiceDomainBeforePresentation() throws {
    for items in [
      [("é", "Composed", UInt8(0)), ("e\u{301}", "Decomposed", UInt8(1))],
      [("保存😀", "Save copy 😀", UInt8(1))], (0..<1024).map { (String($0), "Action \($0)", UInt8(1)) },
    ] {
      var reader = WireReader(try bytes(items))
      _ = try HostCommand.decode(&reader)
      #expect(reader.remaining == 0)
    }
    var maximum = WireReader(
      try bytes([
        (String(repeating: "x", count: ProtocolLimits.maxStringBytes - 5), "Maximum ID", 1)
      ]))
    _ = try HostCommand.decode(&maximum)
    #expect(throws: (any Error).self) {
      var oversized = WireReader(
        try bytes([
          (
            String(repeating: "x", count: ProtocolLimits.maxStringBytes - 4), "Oversized response",
            1
          )
        ]))
      _ = try HostCommand.decode(&oversized)
    }
    let valid = try bytes([("a", "Action", 1)])
    for count in 0..<valid.count {
      #expect(throws: (any Error).self) {
        var reader = WireReader(valid.prefix(count))
        _ = try HostCommand.decode(&reader)
      }
    }
    for items in [
      [], [("", "Action", 1)], [("a", " \n\t", 1)], [("a", "Action", 2)],
      [("a", "A", 1), ("a", "B", 0)],
      (0..<1025).map { (String($0), "Action", UInt8(1)) },
    ] {
      #expect(throws: (any Error).self) {
        var reader = WireReader(try bytes(items))
        _ = try HostCommand.decode(&reader)
      }
    }
  }
}
