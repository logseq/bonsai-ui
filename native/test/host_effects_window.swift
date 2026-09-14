import AppKit
import SwiftUI

@main struct HostEffectsWindowAcceptance: App {
  private let pasteboard: NSPasteboard
  private let applicationBridge: HostEffectsApplicationBridge
  @State private var session: BonsaiSession
  init() {
    let applicationBridge = HostEffectsApplicationBridge()
    self.applicationBridge = applicationBridge
    let pasteboard = NSPasteboard.withUniqueName()
    let windowHost = NativeWindowHost()
    self.pasteboard = pasteboard
    _session = State(
      initialValue: BonsaiSession(
        hostService: NativeHostService(pasteboard: pasteboard, windowHost: windowHost),
        windowHost: windowHost, applicationBridge: applicationBridge.bridge))
  }
  var body: some Scene {
    Window("Host Effects Acceptance", id: "host-effects-acceptance") {
      BonsaiApplicationView(entrypoint: "host_effects", session: session)
        .frame(minWidth: 360, minHeight: 320)
        .task { await verify(session, pasteboard: pasteboard) }
    }.defaultSize(width: 640, height: 480)
  }
}

@MainActor private func verify(_ session: BonsaiSession, pasteboard: NSPasteboard) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else {
      throw failure("Missing Host Effects window")
    }
    func waitText(_ text: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if accessibilityElements(host).contains(where: { $0.value == text || $0.label == text }) {
          return
        }
      }
      throw failure("Missing host response: \(text)")
    }
    func press(_ title: String) throws {
      guard
        let control = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title
        }),
        control.enabled && control.press()
      else { throw failure("Cannot press \(title)") }
    }
    try await waitText("No host request has run")
    var observedEnvironment = false
    for _ in 0..<100 {
      try await settleAccessibility(host)
      observedEnvironment = accessibilityElements(host).contains {
        ($0.label ?? $0.value ?? "").hasPrefix("Environment: platform=macos|")
      }
      if observedEnvironment { break }
    }
    guard observedEnvironment else { throw failure("Missing reactive native environment status") }
    try press("Choose action")
    var actionSheet: NSWindow?
    for _ in 0..<100 {
      if let candidate = window.attachedSheet, candidate.isVisible {
        actionSheet = candidate
        break
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    guard let actionHost = actionSheet?.contentView else { throw failure("Missing action chooser") }
    try await settleAccessibility(actionHost)
    var choiceViews = [actionHost]
    var choiceElements: [AccessibilityElement] = []
    while let view = choiceViews.popLast() {
      choiceViews.append(contentsOf: view.subviews)
      choiceElements.append(contentsOf: accessibilityElements(view))
    }
    guard
      let duplicate = choiceElements.first(where: {
        $0.role == "AXButton" && $0.label == "Duplicate item"
      }), duplicate.press()
    else { throw failure("Cannot choose Duplicate item") }
    try await waitText("Action: duplicate")
    for (label, expected) in [
      ("Choose date", "Date: 2024-02-29"),
      ("Choose date range", "Range: 2024-02-29/2024-03-01"),
      ("Choose time", "Time: 23:59"),
    ] {
      try press(label)
      for _ in 0..<100 {
        if window.attachedSheet?.isVisible == true { break }
        try await Task.sleep(for: .milliseconds(20))
      }
      guard let content = window.attachedSheet?.contentView else {
        throw failure("Missing picker sheet")
      }
      try await settleAccessibility(content)
      guard
        let save = accessibilityElements(content).first(where: {
          $0.role == "AXButton" && $0.label == "Save"
        }), save.press()
      else { throw failure("Missing picker Save action") }
      try await waitText(expected)
    }
    for kind in ["light", "medium", "heavy", "selection"] {
      try press("Haptic " + kind)
      try await waitText("Haptic: " + kind + " requested")
    }
    func exerciseNotifications() async throws {
      try press("Show notification")
      try await waitText("Changes saved")
      try press("Undo")
      try await waitText("Notification: action")
      try press("Show notification")
      try await waitText("Changes saved")
      try press("Dismiss notification")
      try await waitText("Notification: dismissed")
      try press("Show notification")
      try await waitText("Changes saved")
      try press("Cancel notification")
      try await waitText("Notification: cancelled")
      try press("Show timed notification")
      try await waitText("Refresh complete")
      try await waitText("Notification: timed out")
      guard
        !accessibilityElements(host).contains(where: {
          $0.role == "AXButton" && $0.label == "Dismiss notification"
        })
      else { throw failure("Completed notification is still displayed") }
    }
    try await exerciseNotifications()
    try press("Read application bundle")
    try await waitText("Application bundle: org.bonsai-swiftui.test.host-effects-window")
    NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
    try await waitText("Application time zone: \(TimeZone.autoupdatingCurrent.identifier)")
    func filePanel() async throws -> NSSavePanel {
      for _ in 0..<100 {
        if let panel = window.attachedSheet as? NSSavePanel, panel.isVisible { return panel }
        try await Task.sleep(for: .milliseconds(50))
      }
      throw failure("Missing native file panel")
    }
    try press("Import files")
    let importer = try await filePanel()
    guard let open = importer as? NSOpenPanel, open.allowsMultipleSelection else {
      throw failure("File importer did not enable multiple selection")
    }
    importer.cancel(nil)
    try await waitText("File import cancelled")
    try press("Export file")
    let exporter = try await filePanel()
    guard !(exporter is NSOpenPanel), exporter.nameFieldStringValue == "Bonsai.txt" else {
      throw failure("File exporter did not preserve the suggested filename")
    }
    exporter.cancel(nil)
    try await waitText("File export cancelled")
    pasteboard.setString("Native macOS 本地😀", forType: .string)
    try press("Read clipboard")
    try await waitText("Clipboard: Native macOS 本地😀")
    try press("Write clipboard")
    try await waitText("Clipboard write completed")
    guard pasteboard.string(forType: .string) == "Written by Bonsai SwiftUI" else {
      throw failure("Native write did not reach the named pasteboard")
    }
    window.setContentSize(CGSize(width: 360, height: 400))
    try await settleAccessibility(host)
    try await exerciseNotifications()
    try press("Read clipboard")
    try await waitText("Clipboard: Written by Bonsai SwiftUI")
    try press("Read platform information")
    try await waitText(
      "Platform: macos\nOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)\nLocale: \(Locale.autoupdatingCurrent.identifier)"
    )
    try press("Rename window")
    try await waitText("Window title updated")
    guard window.title == "Bonsai SwiftUI 本地😀" else {
      throw failure("Window title request did not reach the owning native window")
    }
    try press("Read platform information")
    try await waitText(
      "Platform: macos\nOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)\nLocale: \(Locale.autoupdatingCurrent.identifier)"
    )
    guard window.title == "Bonsai SwiftUI 本地😀" else {
      throw failure("An unchanged application title overwrote the requested window title")
    }
    try press("Resize window")
    try await waitText("Window size updated")
    let contentSize = window.contentRect(forFrameRect: window.frame).size
    guard abs(contentSize.width - 760) < 1, abs(contentSize.height - 560) < 1 else {
      throw failure("Window size request did not resize native content: \(contentSize)")
    }
    func fields(_ view: NSView) -> [NSTextField] {
      if let field = view as? NSTextField { return [field] }
      return view.subviews.flatMap(fields)
    }
    guard let field = fields(host).first(where: { $0.accessibilityLabel() == "URL" }) else {
      throw failure("Missing URL field")
    }
    let receiver = try URLReceiverFixture()
    defer { receiver.close() }
    try await receiver.waitUntilRegistered()
    func editURL(_ text: String) async throws {
      field.selectText(nil)
      guard let editor = field.currentEditor() as? NSTextView else {
        throw failure("Missing URL field editor")
      }
      editor.insertText(
        text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      for _ in 0..<10 { try await settleAccessibility(host) }
    }
    try await editURL(receiver.url("ocaml"))
    try press("Clear focus")
    try await waitText("Input focus cleared")
    guard field.currentEditor() == nil else {
      throw failure("Clear focus left the URL input active")
    }
    try press("Open URL")
    session.isActive = false
    try await Task.sleep(for: .milliseconds(100))
    guard receiver.received.isEmpty else { throw failure("Inactive URL request launched an app") }
    session.isActive = true
    try await waitText("URL opened")
    try await receiver.waitForCount(1)
    guard receiver.received == [receiver.url("ocaml")] else {
      throw failure("The actual OCaml request did not reach the native receiver")
    }
    try await editURL("relative/path")
    try press("Open URL")
    try await waitText("URL open failed")
    try await editURL(receiver.url("closed"))
    try press("Open URL")
    await session.close()
    try await Task.sleep(for: .milliseconds(100))
    guard receiver.received.count == 1 else { throw failure("Closed session launched a URL") }
    receiver.close()
    pasteboard.releaseGlobally()
    print(
      "PASS: actual Host Effects native window executes notifications, application requests/events, pasteboard, window and native URL requests through OCaml"
    )
    fflush(stdout)
    exit(0)
  } catch {
    await session.close()
    pasteboard.releaseGlobally()
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func failure(_ text: String) -> NSError {
  NSError(
    domain: "HostEffectsWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
