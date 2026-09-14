import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor struct TextFieldTests {
  private func snapshot(
    _ text: String = "Draft", document: UInt64 = 1, accepted: UInt64 = 0,
    mode: TextUpdateMode = .forceReplace
  ) throws -> TextSnapshot {
    try TextSnapshot(
      sessionID: 19, documentRevision: document, acceptedLocalRevision: accepted,
      mode: mode,
      value: TextValue(text: text, selection: NSRange(location: text.utf16.count, length: 0)))
  }
  @Test(arguments: [false, true])
  func nativeFieldEditsAcknowledgeCorrectAndSubmit(secure: Bool) async throws {
    initializeAccessibilityApplication()
    var events: [NativeEventPayload] = []
    let controller = NativeTextFieldController(
      snapshot: try snapshot(), secure: secure,
      configuration: try TextEditorConfiguration(submitOnReturn: true), label: "Title",
      prompt: "Enter title",
      emit: {
        events.append($0)
        return true
      }, failed: { Issue.record($0) })
    let host = NSHostingView(
      rootView: NativeTextFieldView(controller: controller).environment(\.bonsaiFontFamily, "Menlo")
        .frame(width: 320, height: 40))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 360, height: 80), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      controller.dispose()
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect((controller.field is NSSecureTextField) == secure)
    #expect(controller.field.stringValue == "Draft")
    #expect(controller.field.placeholderString == "Enter title")
    #expect(controller.field.font?.familyName == "Menlo")
    controller.field.selectText(nil)
    let editor = try #require(controller.field.currentEditor() as? NSTextView)
    #expect(
      events.contains {
        if case .focusChanged(true) = $0 { return true }
        return false
      })
    editor.insertText(
      "中文😀", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    try await settleAccessibility(host)
    #expect(controller.session.value.text == "中文😀")
    #expect(
      events.contains {
        if case .textEdit(let edit) = $0 { return edit.value.text == "中文😀" }
        return false
      })
    let revision = controller.session.localRevision
    #expect(
      !(try controller.apply(snapshot("stale echo", document: 2, accepted: revision, mode: .ack))))
    #expect(editor.string == "中文😀")
    #expect(
      try controller.apply(
        snapshot("Corrected", document: 3, accepted: revision, mode: .correction)))
    #expect(editor.string == "Corrected")
    editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    try await settleAccessibility(host)
    #expect(
      events.contains {
        if case .textSubmit(let text) = $0 { return text == "Corrected" }
        return false
      })
  }

  @Test func nativeFieldPreservesMarkedTextAndSelectionAcrossAcknowledgment() async throws {
    initializeAccessibilityApplication()
    var events: [NativeEventPayload] = []
    let controller = NativeTextFieldController(
      snapshot: try snapshot(""), secure: false,
      configuration: try TextEditorConfiguration(submitOnReturn: true), label: "Title", prompt: "",
      emit: {
        events.append($0)
        return true
      }, failed: { Issue.record($0) })
    let host = NSHostingView(
      rootView: NativeTextFieldView(controller: controller).frame(width: 320, height: 40))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 360, height: 80), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      controller.dispose()
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    controller.field.selectText(nil)
    let editor = try #require(controller.field.currentEditor() as? NSTextView)
    editor.setMarkedText(
      "拼😀音", selectedRange: NSRange(location: 4, length: 0),
      replacementRange: NSRange(location: 0, length: 0))
    try await settleAccessibility(host)
    #expect(controller.session.value.marked == NSRange(location: 0, length: 4))
    #expect(controller.session.value.selection == NSRange(location: 4, length: 0))
    let revision = controller.session.localRevision
    _ = try controller.apply(snapshot("", document: 2, accepted: revision, mode: .ack))
    #expect(editor.hasMarkedText())
    #expect(editor.string == "拼😀音")
    #expect(
      events.contains {
        if case .textEdit(let edit) = $0 { return edit.value.marked != nil }
        return false
      })
  }

  @Test(arguments: [false, true])
  func fieldRejectsUnadmittedAndOversizeEditsAndReleasesFocusOnDisposal(secure: Bool) async throws {
    initializeAccessibilityApplication()
    var admit = false
    var events: [NativeEventPayload] = []
    let controller = NativeTextFieldController(
      snapshot: try snapshot("OK"), secure: secure,
      configuration: try TextEditorConfiguration(submitOnReturn: true, maxUTF8Bytes: 4),
      label: "Title", prompt: "",
      emit: {
        events.append($0)
        return admit
      }, failed: { Issue.record($0) })
    let host = NSHostingView(
      rootView: NativeTextFieldView(controller: controller).frame(width: 320, height: 40))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 360, height: 80), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      controller.dispose()
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    controller.field.selectText(nil)
    let editor = try #require(controller.field.currentEditor() as? NSTextView)
    editor.insertText(
      "No", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    try await settleAccessibility(host)
    #expect(editor.string == "OK")
    admit = true
    editor.insertText(
      "Too long", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    #expect(editor.string == "OK")
    try await settleAccessibility(host)
    #expect(editor.string == "OK")
    #expect(
      events.contains {
        if case .textLimitReached = $0 { return true }
        return false
      })
    controller.configure(try TextEditorConfiguration(readOnly: true))
    #expect(!controller.field.isEditable && controller.field.isSelectable)
    editor.insertText(
      "No", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    try await settleAccessibility(host)
    #expect(controller.session.value.text == "OK")
    #expect(controller.field.stringValue == "OK")
    controller.configure(try TextEditorConfiguration(enabled: false))
    #expect(!controller.field.isEnabled)
    controller.configure(try TextEditorConfiguration())
    controller.field.selectText(nil)
    let focusedEditor = controller.field.currentEditor()
    controller.dispose()
    #expect(controller.field.delegate == nil)
    #expect(window.firstResponder !== focusedEditor)
  }
}

extension TextFieldTests {
  @Test(arguments: [false, true])
  func autofocusWaitsForPresentationAndDoesNotStealFocusAfterFirstUse(secure: Bool) async throws {
    initializeAccessibilityApplication()
    var events: [NativeEventPayload] = []
    let controller = NativeTextFieldController(
      snapshot: try snapshot(), secure: secure,
      configuration: try TextEditorConfiguration(), label: "Autofocus", prompt: "",
      emit: {
        events.append($0)
        return true
      }, failed: { Issue.record($0) })
    controller.configureTraits(TextFieldTraits(autofocus: true))
    let host = NSHostingView(
      rootView: NativeTextFieldView(controller: controller).frame(width: 300, height: 40))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 320, height: 100), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      controller.dispose()
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    window.makeFirstResponder(nil)
    controller.setPresentationActive(false)
    try await settleAccessibility(host)
    #expect(controller.field.currentEditor() == nil)
    controller.setPresentationActive(true)
    try await settleAccessibility(host)
    #expect(controller.field.currentEditor() != nil)
    #expect(
      events.contains {
        if case .focusChanged(true) = $0 { return true }
        return false
      })
    window.makeFirstResponder(nil)
    controller.setPresentationActive(false)
    controller.setPresentationActive(true)
    try await settleAccessibility(host)
    #expect(controller.field.currentEditor() == nil)
    controller.configureTraits(TextFieldTraits(autofocus: false))
    controller.configure(try TextEditorConfiguration(enabled: false))
    controller.configureTraits(TextFieldTraits(autofocus: true))
    try await settleAccessibility(host)
    #expect(controller.field.currentEditor() == nil)
    controller.configure(try TextEditorConfiguration())
    try await settleAccessibility(host)
    #expect(controller.field.currentEditor() != nil)
    controller.dispose()
    controller.configureTraits(TextFieldTraits(autofocus: false))
    controller.configureTraits(TextFieldTraits(autofocus: true))
    controller.setPresentationActive(true)
    try await settleAccessibility(host)
    #expect(controller.field.currentEditor() == nil)
  }
}
