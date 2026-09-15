import SwiftUI
import UIKit

@testable import BonsaiSwiftUI

// This host renders the actual OCaml entrypoint. Only acceptance actions live here.
@MainActor @Observable private final class AcceptanceSettings {
  var width: CGFloat?
  var type = DynamicTypeSize.large
  var legibility: LegibilityWeight = UIAccessibility.isBoldTextEnabled ? .bold : .regular
}

@main struct NoteDeviceAcceptance: App {
  @State private var session = BonsaiSession()
  @State private var settings = AcceptanceSettings()
  var body: some Scene {
    WindowGroup {
      BonsaiApplicationView(entrypoint: "note", session: session)
        .frame(width: settings.width)
        .dynamicTypeSize(settings.type)
        .environment(\.legibilityWeight, settings.legibility)
        .task { await NoteAcceptance(session: session, settings: settings).run() }
    }
  }
}

@MainActor private final class NoteAcceptance: NSObject {
  let session: BonsaiSession
  let settings: AcceptanceSettings
  let output = URL.documentsDirectory.appending(path: "note-acceptance")
  var keyboardFrame: CGRect?
  var results: [String] = []
  var metrics: [String: Double] = [:]
  init(session: BonsaiSession, settings: AcceptanceSettings) {
    self.session = session
    self.settings = settings
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(keyboardChanged(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
  }
  @objc func keyboardChanged(_ notification: Notification) {
    keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
  }
  func require(_ value: Bool, _ message: String) throws {
    if !value {
      throw NSError(
        domain: "NoteAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  func settle() async throws {
    for _ in 0..<24 { try await Task.sleep(for: .milliseconds(50)) }
    for _ in 0..<600 {
      if UIApplication.shared.applicationState == .active { return }
      try await Task.sleep(for: .milliseconds(50))
    }
    try require(false, "The device must remain unlocked with the acceptance app active")
  }
  func window() throws -> UIWindow {
    guard
      let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        .flatMap(\.windows).first(where: { $0.isKeyWindow && !$0.isHidden })
    else { throw NSError(domain: "NoteAcceptance", code: 2) }
    return window
  }
  func descendants(_ node: RenderNodeState) -> [RenderNodeState] {
    [node] + node.children.flatMap(descendants)
  }
  func named(_ node: RenderNodeState, _ name: String) -> Bool {
    descendants(node).contains {
      switch $0.properties {
      case .semantics(let value): return value.label == name
      case .text(let value): return value.value == name
      default: return false
      }
    }
  }
  func button(_ name: String) throws -> RenderNodeState {
    guard
      let node = session.tree.nodes.values.first(where: {
        if case .button = $0.properties { return named($0, name) }
        return false
      })
    else { throw NSError(domain: "Missing button: \(name)", code: 3) }
    return node
  }
  func click(_ name: String) async throws {
    try require(session.activate(try button(name)), "Rejected button: \(name)")
    try await settle()
  }
  func menu(_ name: String, _ id: Int64) async throws {
    guard
      let node = session.tree.nodes.values.first(where: {
        $0.menuController != nil && named($0, name)
      })
    else { throw NSError(domain: "Missing menu: \(name)", code: 4) }
    try require(node.menuController!.select(id, emit: node.emit), "Rejected menu: \(name)")
    try await settle()
  }
  func text(_ value: String) -> Bool {
    session.tree.nodes.values.contains {
      if case .text(let text) = $0.properties { return text.value == value }
      return false
    }
  }
  func frame(_ node: RenderNodeState) async throws -> CGRect {
    guard let registry = node.layoutTarget.registry else {
      throw NSError(domain: "Detached layout", code: 5)
    }
    return try await registry.measure(node.layoutTarget, valid: { true })
  }
  func scrolls(_ view: UIView) -> [UIScrollView] {
    (view as? UIScrollView).map { [$0] + view.subviews.flatMap(scrolls) }
      ?? view.subviews.flatMap(scrolls)
  }
  func scroll() throws -> UIScrollView {
    guard
      let scroll = try scrolls(window()).filter({ !$0.isHidden && $0.bounds.height > 100 })
        .max(by: { $0.contentSize.height < $1.contentSize.height })
    else { throw NSError(domain: "Missing scroll view", code: 6) }
    return scroll
  }
  func capture(_ name: String) throws {
    let window = try window()
    try require(
      UIApplication.shared.applicationState == .active, "Capture requires an active physical app")
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    try image.pngData()!.write(to: output.appending(path: "\(name).png"), options: .atomic)
    metrics["viewportWidth"] = window.bounds.width
    metrics["viewportHeight"] = window.bounds.height
    metrics["scale"] = window.screen.scale
  }
  func focusSearch() async throws {
    let field = try session.tree.nodes.values.compactMap({ $0.fieldController?.field })
      .first(where: { $0.window != nil }).unwrap("Missing search field")
    try require(field.becomeFirstResponder(), "Search refused focus")
    try await settle()
    for node in session.tree.nodes.values {
      if case .sheet(let sheet) = node.properties, sheet.presented {
        metrics["focusedSheetFraction"] = sheet.configuration.fraction
      }
    }
    try require(
      field.isFirstResponder && (keyboardFrame?.intersection(try window().bounds).height ?? 0) > 100,
      "Search focus lost: first=\(field.isFirstResponder), enabled=\(field.isEnabled), attached=\(field.window != nil), keyboard=\(String(describing: keyboardFrame)), retained=\(session.tree.nodes.values.contains { $0.fieldController?.field === field })"
    )
  }
  func backdropSample(_ name: String) throws -> [Double] {
    let data = try Data(contentsOf: output.appending(path: "\(name).png"))
    let image = try UIImage(data: data).unwrap("Missing material capture").cgImage
      .unwrap("Missing material pixels")
    let scale = try window().screen.scale
    // Empty space to the right of the personal template, inside the sheet.
    let patch = try image.cropping(
      to: CGRect(
        x: 260 * scale, y: 245 * scale,
        width: 80 * scale, height: 70 * scale)
    )
    .unwrap("Missing backdrop patch")
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try CGContext(
      data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    .unwrap("Missing sample context")
    context.interpolationQuality = .high
    context.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return pixel.prefix(3).map { Double($0) }
  }
  func record(_ step: String) throws {
    results.append(step)
    try status("running")
  }
  func status(_ state: String, error: String? = nil) throws {
    let data: [String: Any] = [
      "status": state, "error": error ?? "", "checks": results, "metrics": metrics,
      "systemVersion": UIDevice.current.systemVersion,
      "reduceMotion": UIAccessibility.isReduceMotionEnabled,
      "darkerSystemColors": UIAccessibility.isDarkerSystemColorsEnabled,
      "windowContrast": (try? window().traitCollection.accessibilityContrast.rawValue) ?? -1,
      "boldText": UIAccessibility.isBoldTextEnabled,
      "captureLegibility": settings.legibility == .regular ? "regular" : "system",
      "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
      "revision": session.displayedRevision,
      "capture": "Active physical-device UIWindow.drawHierarchy; actual Note OCaml entrypoint",
    ]
    try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
      .write(to: output.appending(path: "result.json"), options: .atomic)
  }
  func run() async {
    UIApplication.shared.isIdleTimerDisabled = true
    defer {
      UIApplication.shared.isIdleTimerDisabled = false
      NotificationCenter.default.removeObserver(self)
    }
    do {
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      try await settle()
      try require(
        session.displayedRevision > 0 && text("Cornell Note Template"), "Initial note not presented"
      )
      try capture("cornell-system")
      settings.legibility = .regular
      try await settle()
      try capture("cornell")
      for name in ["Templates", "Share preview", "Edit note"] {
        let bounds = try await frame(button(name))
        try require(bounds.width >= 44 && bounds.height >= 44, "Small target: \(name) \(bounds)")
      }
      try record("Initial Cornell and 44-point button targets")
      try await click("Templates")
      try capture("templates")
      try await focusSearch()
      try capture("templates-focused")
      try await click("Close templates")
      try await menu("Document theme", 2)
      try await click("Templates")
      try capture("templates-cool")
      try await focusSearch()
      try capture("templates-focused-cool")
      let warmSample = try backdropSample("templates")
      let coolSample = try backdropSample("templates-cool")
      let response = zip(warmSample, coolSample).map { abs($0 - $1) }.max()!
      metrics["sheetBackdropResponseRGB"] = response
      try require(
        response >= 12,
        "Sheet material hides its backdrop: warm \(warmSample), cool \(coolSample)")
      let focusedWarm = try backdropSample("templates-focused")
      let focusedCool = try backdropSample("templates-focused-cool")
      let focusedResponse = zip(focusedWarm, focusedCool).map { abs($0 - $1) }.max()!
      metrics["focusedSheetBackdropResponseRGB"] = focusedResponse
      // iOS 26 grows the sheet for keyboard avoidance and makes full-height
      // presentations opaque. Record the effect without overriding system behavior.
      try await click("Close templates")
      try await menu("Document theme", 1)
      try await click("Templates")
      try record("Sheet material responds to the real document backdrop")
      guard
        let field = session.tree.nodes.values.compactMap({ $0.fieldController?.field }).first(
          where: { $0.window != nil })
      else { throw NSError(domain: "Missing native search", code: 7) }
      field.becomeFirstResponder()
      field.text = "no matching template"
      field.sendActions(for: .editingChanged)
      try await settle()
      try require(text("No templates found"), "Native search did not reach OCaml")
      try capture("search-empty")
      try await click("Clear search")
      try require(text("MY TEMPLATES"), "Clear failed")
      field.resignFirstResponder()
      try await settle()
      try require(!field.isFirstResponder, "Search did not leave editing")
      try capture("templates-after-keyboard")
      let restored = try backdropSample("templates-after-keyboard")
      let restorationError = zip(warmSample, restored).map { abs($0 - $1) }.max()!
      metrics["sheetAfterKeyboardRestorationRGBError"] = restorationError
      try require(restorationError <= 3, "Sheet material did not return after keyboard dismissal")
      try await click("Reading · Robert Pirosh")
      try require(text("Robert Pirosh"), "Reading selection failed")
      try capture("reading")
      try record("Native search, empty state, clear and reading selection")
      let viewport = try scroll()
      viewport.setContentOffset(
        CGPoint(
          x: 0,
          y: max(
            0,
            viewport.contentSize.height - viewport.bounds.height
              + viewport.adjustedContentInset.bottom)), animated: false)
      try await settle()
      guard
        let end = session.tree.nodes.values.first(where: {
          if case .text(let value) = $0.properties { return value.value == "End of document" }
          return false
        })
      else { throw NSError(domain: "Missing document end", code: 8) }
      let endFrame = try await frame(end)
      let editFrame = try await frame(button("Edit note"))
      metrics["documentEndY"] = endFrame.maxY
      metrics["bottomControlsY"] = editFrame.minY
      try capture("reading-end")
      try require(
        endFrame.maxY <= editFrame.minY && endFrame.minY >= 0,
        "Bottom controls obscure final content")
      try record("Native scrolling exposes final content above anchored controls")
      try await click("Templates")
      guard
        let sheet = session.tree.nodes.values.first(where: {
          $0.presentationController?.presented == true
        }),
        let presentation = sheet.presentationController
      else { throw NSError(domain: "Missing native sheet", code: 11) }
      try require(presentation.requestDismissal(emit: sheet.emit), "Native dismissal was rejected")
      try await settle()
      try require(text("Robert Pirosh"), "Native dismissal changed the note")
      try await click("Templates")
      try await click("Close templates")
      try require(text("Robert Pirosh"), "Dismissal replaced the note")
      try await click("Templates")
      try await click("Cornell Note Template")
      try await click("Key Points")
      try await click("Supporting Details")
      try require(
        text("Write one clear idea, then connect it to what you already know.")
          && text("Add examples, observations and questions that support the main idea."),
        "Disclosures did not expand independently")
      try await click("Key Points")
      try require(
        !text("Write one clear idea, then connect it to what you already know.")
          && text("Add examples, observations and questions that support the main idea."),
        "Collapse affected sibling")
      try record("Back, close and independent disclosure actions")
      try await click("Edit note")
      guard
        let title = session.tree.nodes.values.compactMap({ $0.fieldController?.field }).first(
          where: { $0.window != nil }),
        let editor = session.tree.nodes.values.compactMap({ $0.textController?.view }).first(
          where: { $0.window != nil })
      else { throw NSError(domain: "Missing native editors", code: 9) }
      title.becomeFirstResponder()
      title.text = "Field notes 🌿"
      title.sendActions(for: .editingChanged)
      try await settle()
      editor.becomeFirstResponder()
      editor.selectAll(nil)
      editor.insertText("A physical-device observation.\nA second line.")
      try await settle()
      let editorBounds = editor.convert(editor.bounds, to: try window())
      let doneBounds = try await frame(button("Done"))
      metrics["editorBottomY"] = editorBounds.maxY
      metrics["doneBottomY"] = doneBounds.maxY
      try require(
        editor.isFirstResponder && editorBounds.height > 80 && doneBounds.minY >= 0
          && doneBounds.maxY < editorBounds.maxY, "Editor or Done is not usable with the keyboard")
      guard let keyboardFrame, keyboardFrame.minY < (try window()).bounds.height else {
        throw NSError(domain: "Software keyboard was not presented", code: 10)
      }
      metrics["keyboardTopY"] = keyboardFrame.minY
      try require(
        editorBounds.maxY <= keyboardFrame.minY + 1 && doneBounds.maxY < keyboardFrame.minY,
        "The software keyboard obscures the editor or Done")
      try capture("editing-keyboard")
      try await click("Done")
      try require(
        text("Field notes 🌿") && text("A physical-device observation.\nA second line."),
        "Native edits did not persist")
      try record("Actual UIKit title/body input and Done preserve edits")
      try await menu("Document theme", 2)
      try await menu("Insert block", 1)
      try await menu("Insert block", 2)
      try require(
        text("A new paragraph to explore.") && text("Review this note"), "Mock insertion failed")
      try await click("Share preview")
      try require(text("Share preview"), "Mock share failed")
      try await click("Close preview")
      try await menu("Document tools", 1)
      try require(text("Word count preview"), "Mock tools failed")
      try await click("Close preview")
      try record("Theme, both insertions and named mock results")
      try await click("Templates")
      try await click("Cornell Note Template")
      try require(
        !text("A new paragraph to explore.") && text("Cornell Note Template"),
        "Template seed was mutated")
      settings.width = 320
      try await settle()
      let narrow = try scroll()
      let normalHeight = narrow.contentSize.height
      metrics["narrowNormalHeight"] = normalHeight
      try require(narrow.contentSize.width <= 321, "Narrow content overflows horizontally")
      try capture("narrow")
      settings.type = .accessibility2
      try await settle()
      metrics["narrowLargeTextHeight"] = narrow.contentSize.height
      try capture("narrow-large-text")
      try require(
        narrow.contentSize.height > normalHeight + 100 && narrow.contentSize.width <= 321,
        "Larger text does not reflow")
      try record("Fresh seed, 320-point width and larger text reflow")
      settings.width = nil
      settings.type = .large
      try await settle()
      try status("passed")
    } catch {
      try? capture("failure")
      try? status("failed", error: String(describing: error))
    }
  }
}

extension Optional {
  fileprivate func unwrap(_ message: String) throws -> Wrapped {
    guard let value = self else {
      throw NSError(
        domain: "NoteAcceptance", code: 8,
        userInfo: [NSLocalizedDescriptionKey: message])
    }
    return value
  }
}
