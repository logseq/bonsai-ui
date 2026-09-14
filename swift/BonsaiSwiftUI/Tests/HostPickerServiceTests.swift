import AppKit
import Observation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor @Observable private final class PickerSettings { var phase = ScenePhase.active }
@MainActor private struct PickerServiceHost: View {
  let session: BonsaiSession
  let settings: PickerSettings
  var body: some View {
    BonsaiApplicationView(entrypoint: "native-picker-service", session: session)
      .environment(\.scenePhase, settings.phase).allowsWindowActivationEvents(true)
  }
}
@MainActor private final class PickerServiceScene {
  let session: BonsaiSession
  let settings = PickerSettings()
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
    let hosting = NSHostingView(rootView: PickerServiceHost(session: session, settings: settings))
    hosting.sizingOptions = []
    host = hosting
    window.contentView = hosting
    window.orderFront(nil)
    try await wait { self.session.displayedRevision > 0 && self.events != nil }
    try await settleAccessibility(hosting)
  }
  var status: String {
    session.tree.nodes.values.compactMap {
      if case .text(let value) = $0.properties, value.value.hasPrefix("Pickers:") {
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
      "\(status); displayed=\(session.displayedRevision); active=\(session.isActive); visible=\(session.isVisible); tree=\(session.tree.nodes.count); labels=\(host.map { accessibilityElements($0).compactMap(\.label) } ?? []); sheet=\(String(describing: sheet)); choices=\(choices.compactMap(\.label))"
    )
  }
  func settle() async throws { for _ in 0..<12 { try await tick() } }
  func close() async {
    window.orderOut(nil)
    window.contentView = nil
    host = nil
    await session.close()
  }
}

extension NativeRuntimeTests {
  @Test func hostPickersFixtureStarts() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-picker-service")
    do {
      let frame = try await runtime.pump(monotonicNanoseconds: 1)
      #expect(frame.bytes.range(of: Data("Pickers:".utf8)) != nil)
      _ = try FrameState().staging(WireFrame.decode(frame.bytes))
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
  @Test @MainActor func hostPickersEditNativeControlsBeforeCommittingToOcaml() async throws {
    let scene = PickerServiceScene(width: 360)
    do {
      try await scene.start()
      for mode in ["date", "range", "time", "historical", "default"] {
        try await scene.show(mode, mode: mode)
        #expect(try #require(scene.sheet).frame.width <= scene.window.frame.width)
        #expect(!scene.status.contains(mode + "="))
        if mode == "date" || mode == "range" {
          let popup = try #require(
            scene.nativeViews.compactMap { $0 as? NSPopUpButton }.first {
              $0.itemArray.contains { $0.title == "2025" }
            })
          let menu = try #require(popup.menu)
          let item = try #require(menu.items.first { $0.title == "2025" })
          menu.performActionForItem(at: menu.index(of: item))
        }
        if mode == "time" {
          let control = try #require(scene.nativeViews.compactMap { $0 as? NSDatePicker }.first)
          #expect(control.timeZone?.secondsFromGMT() == 0)
          control.dateValue = try CivilTime(hour: 0, minute: 1).dateForPicker()
          #expect(control.sendAction(control.action, to: control.target))
        }
        try await scene.settle()
        #expect(!scene.status.contains(mode + "="))
        #expect(try scene.action("Save").press())
        let expected = [
          "date": "2025-02-28", "range": "2025-02-28/2025-02-28",
          "time": "00:01", "historical": "1582-10-10", "default": "2024-02-10",
        ][mode]!
        try await scene.wait {
          scene.status.contains(mode + "=" + expected + ";") && scene.sheet == nil
        }
      }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func hostPickersCancelBlockAndFenceRealSheets() async throws {
    let scene = PickerServiceScene()
    do {
      try await scene.start()
      let background = try scene.rootButton("Background action")
      for mode in ["date", "range", "time"] {
        try await scene.show(mode, mode: mode)
        let retired = try scene.action("Save")
        _ = background.press()
        try scene.send("show:busy-" + mode + ":menu")
        try await scene.wait { scene.status.contains("busy-" + mode + "=error;") }
        #expect(scene.text("Background: 0"))
        try scene.send("file:file-" + mode)
        try await scene.wait { scene.status.contains("file-" + mode + "=error;") }
        #expect(try scene.action("Cancel").press())
        try await scene.wait { scene.status.contains(mode + "=dismissed;") && scene.sheet == nil }
        try await scene.show("cancel-" + mode, mode: mode)
        _ = retired.press()
        try await scene.settle()
        #expect(!scene.status.contains("cancel-" + mode + "="))
        try scene.send("cancel:cancel-" + mode)
        try await scene.wait {
          scene.status.contains("cancel-" + mode + "=cancelled;") && scene.sheet == nil
        }
      }
      try await scene.show("inactive", mode: "date")
      scene.settings.phase = .inactive
      try await scene.wait { scene.sheet == nil }
      scene.settings.phase = .active
      try await scene.wait { scene.status.contains("inactive=cancelled;") }
      try await scene.show("closing", mode: "time")
      let retired = try scene.action("Save")
      await scene.close()
      try await scene.start()
      try await scene.show("restart", mode: "range")
      _ = retired.press()
      try await scene.settle()
      #expect(scene.status == "Pickers:")
      #expect(try scene.action("Cancel").press())
      try await scene.wait { scene.status == "Pickers:restart=dismissed;" }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }
}

extension PickerServiceScene {
  fileprivate var nativeViews: [NSView] {
    var pending = sheet?.contentView.map { [$0] } ?? []
    var result: [NSView] = []
    while let view = pending.popLast() {
      result.append(view)
      pending.append(contentsOf: view.subviews)
    }
    return result.reversed()
  }
}

struct HostPickerWireTests {
  private func date(_ year: UInt16, _ month: UInt8, _ day: UInt8) -> Data {
    var writer = WireWriter()
    writer.integer(year)
    writer.integer(month)
    writer.integer(day)
    return writer.bytes
  }
  private func decode(_ kind: UInt16, _ payload: Data) throws {
    var writer = WireWriter()
    writer.integer(UInt64(1))
    writer.integer(kind)
    var reader = WireReader(writer.bytes + payload)
    _ = try HostCommand.decode(&reader)
    guard reader.remaining == 0 else { throw WireError.invalidOperation }
  }
  @Test func pickerWireValidatesCivilValuesBoundsAndNewPayloads() throws {
    let first = date(1, 1, 1)
    let last = date(9999, 12, 31)
    let initial = date(1582, 10, 10)
    let valid: [(UInt16, Data)] = [
      (16, Data([0]) + first + last), (16, Data([1]) + initial + first + last),
      (17, Data([0]) + first + last), (17, Data([1]) + first + last + first + last),
      (18, Data([0, 0, 0])), (18, Data([23, 59, 1])), (18, Data([12, 0, 2])),
    ]
    for (kind, payload) in valid {
      try decode(kind, payload)
      for count in 0..<payload.count {
        #expect(throws: (any Error).self) { try decode(kind, payload.prefix(count)) }
      }
      #expect(throws: (any Error).self) { try decode(kind, payload + Data([0])) }
    }
    let invalid: [(UInt16, Data)] = [
      (16, Data([2]) + first + last), (16, Data([0]) + last + first),
      (16, Data([1]) + date(1500, 2, 29) + first + last),
      (16, Data([1]) + first + initial + last), (16, Data([0]) + date(0, 1, 1) + last),
      (17, Data([1]) + last + first + first + last),
      (17, Data([1]) + first + last + initial + last),
      (18, Data([24, 0, 0])), (18, Data([0, 60, 0])), (18, Data([0, 0, 3])),
    ]
    for (kind, payload) in invalid {
      #expect(throws: (any Error).self) { try decode(kind, payload) }
    }
  }
}
