import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor struct SliderTests {
  @Test func invalidDomainsAndIntervalsCannotPublish() throws {
    for upper: Double? in [nil, 80] {
      let store = try NodeStore().staging(
        TreeFixture.frame([TreeFixture.slider(upper: upper), TreeFixture.root(1)])
      ).tree
      for operation in [
        TreeFixture.slider(lower: .nan, upper: upper, update: true),
        TreeFixture.slider(lower: -1, upper: upper, update: true),
        TreeFixture.slider(lower: 101, upper: upper, update: true),
        TreeFixture.slider(upper: upper, minimum: 100, maximum: 0, update: true),
        TreeFixture.slider(
          upper: upper, minimum: -Double.greatestFiniteMagnitude,
          maximum: Double.greatestFiniteMagnitude, update: true),
        TreeFixture.slider(upper: upper, step: 0, update: true),
        TreeFixture.slider(upper: upper, step: .infinity, update: true),
        TreeFixture.slider(upper: upper, step: .leastNonzeroMagnitude, update: true),
        TreeFixture.slider(upper: upper, enabled: 2, update: true),
        TreeFixture.slider(upper: upper, vertical: 2, update: true),
      ] {
        #expect(throws: (any Error).self) {
          try store.staging(TreeFixture.frame([operation], base: 1, revision: 2))
        }
      }
      #expect(store.revision == 1)
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame([TreeFixture.slider(lower: 80, upper: 20), TreeFixture.root(1)]))
    }
  }

  @Test(arguments: [false, true], [false, true])
  func nativeAdjustmentHonorsStepBoundsAndEndOnlyHandlers(ranged: Bool, changes: Bool) async throws
  {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.slider(upper: ranged ? 40 : nil, changes: changes ? 1 : 0),
          TreeFixture.root(1),
        ])
      ).tree)
    var events: [NativeEventPayload] = []
    tree.onInput = { _, payload in
      events.append(payload)
      return true
    }
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }).frame(
        width: 300, height: 80))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    func control(_ title: String) throws -> AccessibilityElement {
      try #require(accessibilityElements(host).first { $0.label == title && $0.role == "AXSlider" })
    }
    let title = ranged ? "Lower" : "Level"
    #expect(try control(title).numericValue == 20)
    #expect(try control(title).increment())
    try await settleAccessibility(host)
    #expect(try control(title).numericValue == 30)
    #expect(
      events.map(\.tag)
        == (changes
          ? [
            ranged ? EventTagId.rangeSliderChanged : EventTagId.sliderChanged,
            ranged ? EventTagId.rangeSliderChangeEnd : EventTagId.sliderChangeEnd,
          ]
          : [ranged ? EventTagId.rangeSliderChangeEnd : EventTagId.sliderChangeEnd]))
    if ranged {
      for _ in 0..<4 {
        _ = try control(title).increment()
        try await settleAccessibility(host)
      }
      #expect(try control(title).numericValue == 40)
      #expect(try control("Upper").numericValue == 40)
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGallerySlidersAcceptRejectAndDisableNativeChanges() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-slider")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 420), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      let original = session.tree.nodes
      func control(_ title: String) throws -> AccessibilityElement {
        try #require(
          accessibilityElements(host).first {
            $0.label == title && ($0.role == "AXSlider" || $0.role == "AXButton")
          })
      }
      func refresh() async throws {
        if try await session.refresh() {
          #expect(try await session.presented(#require(session.ticket)))
        }
        try await settleAccessibility(host)
      }
      #expect(try control("Level").increment())
      try await refresh()
      #expect(try control("Level").numericValue == 30)
      #expect(accessibilityElements(host).contains { $0.value == "Ended: 1" })
      #expect(try control("Lower").increment())
      try await refresh()
      #expect(try control("Lower").numericValue == 30)
      #expect(accessibilityElements(host).contains { $0.value == "Ended: 2" })
      #expect(try control("Vertical level").increment())
      try await refresh()
      #expect(try control("Level").numericValue == 40)
      #expect(accessibilityElements(host).contains { $0.value == "Ended: 3" })
      #expect(try control("Ignore changes").press())
      try await refresh()
      for _ in 0..<2 {
        #expect(try control("Level").increment())
        try await refresh()
        #expect(try control("Level").numericValue == 40)
        #expect(try control("Upper").increment())
        try await refresh()
        #expect(try control("Upper").numericValue == 40)
      }
      #expect(try control("Accept changes").press())
      try await refresh()
      #expect(try control("Disable sliders").press())
      try await refresh()
      #expect(!(try control("Level").enabled))
      _ = try control("Level").increment()
      try await refresh()
      #expect(try control("Level").numericValue == 40)
      #expect(original.allSatisfy { session.tree.nodes[$0.key] === $0.value })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

@MainActor extension SliderTests {
  @Test(arguments: [false, true], [false, true])
  func rangeThumbsCanBeAdjustedFromTheNativeKeyboardFocusLoop(vertical: Bool, rtl: Bool)
    async throws
  {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.slider(upper: 60, vertical: vertical ? 1 : 0), TreeFixture.root(1),
        ])
      ).tree)
    var events: [NativeEventPayload] = []
    tree.onInput = { _, event in
      events.append(event)
      return true
    }
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in })
        .frame(width: vertical ? 80 : 300, height: vertical ? 300 : 80)
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: vertical ? 80 : 300, height: vertical ? 300 : 80),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    window.makeFirstResponder(nil)
    window.selectNextKeyView(nil)
    try await settleAccessibility(host)
    func arrow(increase: Bool) throws {
      let right = increase != rtl
      let character =
        vertical
        ? (increase ? NSUpArrowFunctionKey : NSDownArrowFunctionKey)
        : (right ? NSRightArrowFunctionKey : NSLeftArrowFunctionKey)
      let key = String(UnicodeScalar(character)!)
      let code: UInt16 = vertical ? (increase ? 126 : 125) : (right ? 124 : 123)
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false,
          keyCode: code))
      // NSWindow dispatches key equivalents and SwiftUI key handlers before the responder fallback.
      window.sendEvent(event)
    }
    try arrow(increase: true)
    try await settleAccessibility(host)
    #expect(events.map(\.tag) == [EventTagId.rangeSliderChanged, EventTagId.rangeSliderChangeEnd])
    let selection = try #require(tree.root?.sliderController).selection
    #expect(
      selection == SliderSelection(lower: 30, upper: 60)
        || selection == SliderSelection(lower: 20, upper: 70))
    try arrow(increase: false)
    try await settleAccessibility(host)
    #expect(tree.root?.sliderController?.selection == SliderSelection(lower: 20, upper: 60))
    window.selectNextKeyView(nil)
    try await settleAccessibility(host)
    try arrow(increase: true)
    try await settleAccessibility(host)
    let next = try #require(tree.root?.sliderController).selection
    #expect(next != selection)
    #expect(
      next == SliderSelection(lower: 30, upper: 60)
        || next == SliderSelection(lower: 20, upper: 70))
    #expect(events.count == 6)
  }
}

@MainActor extension SliderTests {
  @Test(arguments: [false, true])
  func nativeAdjustmentReachesFiniteDomainEndpoints(decreasing: Bool) async throws {
    initializeAccessibilityApplication()
    let limit = Double.greatestFiniteMagnitude
    let minimum = decreasing ? -limit : 0
    let maximum = decreasing ? 0 : limit
    let value = (decreasing ? -limit : limit) * 0.99
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.slider(lower: value, minimum: minimum, maximum: maximum, step: nil),
          TreeFixture.root(1),
        ])
      ).tree)
    var events: [NativeEventPayload] = []
    tree.onInput = { _, event in
      events.append(event)
      return true
    }
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    let control = try #require(accessibilityElements(host).first { $0.role == "AXSlider" })
    #expect(decreasing ? control.decrement() : control.increment())
    try await settleAccessibility(host)
    let target = decreasing ? minimum : maximum
    #expect(tree.root?.sliderController?.selection.lower == target)
    #expect(events.count == 2)
    #expect(events.last?.sliderSelection?.lower == target)
  }
}
