import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor struct TextEditorAutofocusTests {
  @Test func autofocusWaitsForNativeAvailabilityAndDoesNotStealFocus() async throws {
    initializeAccessibilityApplication()
    let controller = NativeTextController(
      snapshot: try textSnapshot("Draft"), configuration: try TextEditorConfiguration(),
      emit: { _ in true }, failed: { Issue.record("Unexpected editor failure: \($0)") })
    let host = NSHostingView(rootView: NativeTextEditorView(controller: controller))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 400, height: 240),
      styleMask: [.titled], backing: .buffered, defer: false)
    defer { controller.dispose(); window.orderOut(nil); window.contentView = nil }
    controller.configureAutofocus(true)
    controller.setPresentationActive(true)
    controller.configure(try TextEditorConfiguration(enabled: false))
    window.contentView = host
    window.orderFront(nil)
    try await settleAccessibility(host)
    #expect(window.firstResponder !== controller.view)
    controller.configure(try TextEditorConfiguration(readOnly: true))
    try await settleAccessibility(host)
    #expect(window.firstResponder !== controller.view)
    controller.setPresentationActive(false)
    controller.configure(try TextEditorConfiguration())
    #expect(window.makeFirstResponder(nil))
    try await settleAccessibility(host)
    #expect(window.firstResponder !== controller.view)
    controller.setPresentationActive(true)
    try await settleAccessibility(host)
    #expect(window.firstResponder === controller.view)
    #expect(window.makeFirstResponder(nil))
    controller.setPresentationActive(false)
    controller.setPresentationActive(true)
    controller.setHostEnabled(false)
    controller.setHostEnabled(true)
    try await settleAccessibility(host)
    #expect(window.firstResponder !== controller.view)
    controller.configureAutofocus(false)
    controller.setContentActive(false)
    controller.configureAutofocus(true)
    try await settleAccessibility(host)
    #expect(window.firstResponder !== controller.view)
    controller.setContentActive(true)
    try await settleAccessibility(host)
    #expect(window.firstResponder === controller.view)
    #expect(window.makeFirstResponder(nil))
    controller.configureAutofocus(false)
    controller.setPresentationActive(false)
    controller.configureAutofocus(true)
    controller.configureAutofocus(false)
    controller.setPresentationActive(true)
    try await settleAccessibility(host)
    #expect(window.firstResponder !== controller.view)
    controller.dispose()
    controller.configureAutofocus(true)
    controller.setPresentationActive(true)
    try await settleAccessibility(host)
    #expect(window.firstResponder !== controller.view)
  }
}
