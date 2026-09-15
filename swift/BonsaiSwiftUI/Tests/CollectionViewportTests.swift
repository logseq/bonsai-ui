import AppKit
import Observation
import SwiftUI
import Synchronization
import Testing

@testable import BonsaiSwiftUI

@MainActor private final class RowMarkerView: NSView {
  let index: Int
  init(_ index: Int) {
    self.index = index
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
}

private struct RowMarker: NSViewRepresentable {
  let index: Int
  func makeNSView(context: Context) -> RowMarkerView { RowMarkerView(index) }
  func updateNSView(_ view: RowMarkerView, context: Context) {}
}

@MainActor @Observable private final class CollectionHarness {
  let viewport: CollectionViewport
  var rows = 0..<20
  init(horizontal: Bool = false, initialOffset: Double = 0) throws {
    viewport = try CollectionViewport(
      geometry: CollectionGeometry(count: 10000, defaultExtent: 40), vertical: !horizontal,
      initialOffset: initialOffset)
  }
}

private struct HarnessView: View {
  let model: CollectionHarness
  var body: some View {
    WindowedCollectionView(viewport: model.viewport, firstIndex: model.rows.lowerBound) {
      ForEach(Array(model.rows), id: \.self) { index in
        Text("Row \(index)")
          .frame(
            width: model.viewport.vertical ? nil : model.viewport.geometry.extent(at: index),
            height: model.viewport.vertical ? model.viewport.geometry.extent(at: index) : nil
          )
          .frame(
            maxWidth: model.viewport.vertical ? .infinity : nil,
            maxHeight: model.viewport.vertical ? nil : .infinity
          )
          .background(RowMarker(index: index))
      }
    }
  }
}

@MainActor private func nativeDescendants<T: NSView>(_ root: NSView, _: T.Type) -> [T] {
  (root as? T).map { [$0] } ?? root.subviews.flatMap { nativeDescendants($0, T.self) }
}

@MainActor private func settle(_ hosting: NSView) async throws {
  for _ in 0..<10 {
    hosting.layoutSubtreeIfNeeded()
    hosting.displayIfNeeded()
    try await Task.sleep(for: .milliseconds(10))
  }
}

@MainActor private func moveCollection(
  _ scroll: NSScrollView, to offset: Double, horizontal: Bool, rightToLeft: Bool
) {
  let x =
    rightToLeft
    ? (scroll.documentView?.frame.width ?? 0) - scroll.contentView.bounds.width - offset : offset
  scroll.contentView.scroll(to: horizontal ? CGPoint(x: x, y: 0) : CGPoint(x: 0, y: offset))
  scroll.reflectScrolledClipView(scroll.contentView)
}

@MainActor private func collectionOffset(
  _ scroll: NSScrollView, horizontal: Bool, rightToLeft: Bool
) -> Double {
  let rect = scroll.documentVisibleRect
  return horizontal
    ? (rightToLeft ? (scroll.documentView?.frame.width ?? 0) - rect.maxX : rect.minX) : rect.minY
}

@MainActor private func rowOffset(
  _ row: NSView, in scroll: NSScrollView, horizontal: Bool, rightToLeft: Bool
) -> Double {
  let rect = row.convert(row.bounds, to: scroll.documentView)
  return horizontal
    ? (rightToLeft ? (scroll.documentView?.frame.width ?? 0) - rect.maxX : rect.minX) : rect.minY
}

@Suite(.serialized) struct CollectionViewportTests {
  @Test(
    arguments: [(false, false), (true, false), (true, true)],
    [(false, -6.0), (false, 6.0), (true, -6.0), (true, 6.0)])
  @MainActor func windowRemovalRetainsUnobservedNativeTravel(
    layout: (Bool, Bool), motion: (Bool, Double)
  ) async throws {
    let (horizontal, rightToLeft) = layout
    let (animated, delta) = motion
    let model = try CollectionHarness(horizontal: horizontal)
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: 607.5, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    if animated {
      model.viewport.replace(
        try CollectionGeometry(
          count: 10000, defaultExtent: 40,
          overrides: [CollectionExtent(index: 0, extent: 181.3)]),
        timing: CollectionTiming(expandMilliseconds: 600, collapseMilliseconds: 600))
      try await Task.sleep(for: .milliseconds(40))
    }
    let before = collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft)
    moveCollection(scroll, to: before + delta, horizontal: horizontal, rightToLeft: rightToLeft)
    // Remove the hierarchy before SwiftUI can deliver another geometry callback.
    window.contentView = nil
    let expected = 607.5 + delta + (animated ? 141.3 : 0)
    #expect(abs(model.viewport.leadingOffset - expected) < 1)
    window.contentView = hosting
    try await settle(hosting)
    let remounted = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    #expect(
      abs(collectionOffset(remounted, horizontal: horizontal, rightToLeft: rightToLeft) - expected)
        < 1)
    #expect(abs(model.viewport.leadingOffset - expected) < 1)
  }

  @Test(arguments: [false, true], [-6.0, 6.0])
  @MainActor func directionReplacementPreservesAnimatingNativeTravel(
    rightToLeft: Bool, delta: Double
  ) async throws {
    let model = try CollectionHarness(horizontal: true)
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let oldScroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(oldScroll, to: 607.5, horizontal: true, rightToLeft: rightToLeft)
    try await settle(hosting)
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 181.3)]),
      timing: CollectionTiming(expandMilliseconds: 600, collapseMilliseconds: 600))
    try await Task.sleep(for: .milliseconds(40))
    let before = collectionOffset(oldScroll, horizontal: true, rightToLeft: rightToLeft)
    moveCollection(oldScroll, to: before + delta, horizontal: true, rightToLeft: rightToLeft)
    hosting.rootView = HarnessView(model: model).environment(
      \.layoutDirection, rightToLeft ? .leftToRight : .rightToLeft)
    try await settle(hosting)
    try await Task.sleep(for: .milliseconds(650))
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    let expected = 607.5 + delta + 141.3
    #expect(
      abs(collectionOffset(scroll, horizontal: true, rightToLeft: !rightToLeft) - expected) < 1)
    #expect(abs(model.viewport.leadingOffset - expected) < 1)
    #expect(abs(model.viewport.geometry.extent(at: 0) - 181.3) < 0.001)
  }

  @Test(arguments: [false, true], [false, true])
  @MainActor func directionReplacementRetainsNativeAnchor(horizontal: Bool, rightToLeft: Bool)
    async throws
  {
    let model = try CollectionHarness(horizontal: horizontal)
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    var scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: 607.5, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    hosting.rootView = HarnessView(model: model).environment(
      \.layoutDirection, rightToLeft ? .leftToRight : .rightToLeft)
    try await settle(hosting)
    scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: !rightToLeft) - 607.5) < 1)
    #expect(abs(model.viewport.leadingOffset - 607.5) < 1)
  }

  @Test(arguments: [false, true])
  @MainActor func replacedViewportCannotMoveItsFormerNativeList(horizontal: Bool) async throws {
    let old = try CollectionHarness(horizontal: horizontal)
    let current = try CollectionHarness(horizontal: horizontal)
    let hosting = NSHostingView(rootView: AnyView(HarnessView(model: old)))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    hosting.rootView = AnyView(HarnessView(model: current))
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: 600, horizontal: horizontal, rightToLeft: false)
    try await settle(hosting)
    old.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 200)]))
    try await settle(hosting)
    #expect(abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: false) - 600) < 1)
    current.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 120)]))
    try await settle(hosting)
    #expect(abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: false) - 680) < 1)
  }

  @Test(arguments: [false, true], [false, true])
  @MainActor func detachedViewportRetainsTravelAndRemountsAtItsAnchor(
    horizontal: Bool, rightToLeft: Bool
  ) async throws {
    let model = try CollectionHarness(horizontal: horizontal)
    func content() -> AnyView {
      AnyView(
        HarnessView(model: model).environment(
          \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    }
    let hosting = NSHostingView(rootView: content())
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: 600, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 181.3)]),
      timing: CollectionTiming(expandMilliseconds: 600, collapseMilliseconds: 600))
    try await Task.sleep(for: .milliseconds(40))
    let before = collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft)
    moveCollection(scroll, to: before + 6, horizontal: horizontal, rightToLeft: rightToLeft)
    hosting.rootView = AnyView(EmptyView())
    try await settle(hosting)
    let retiredOffset = collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft)
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 220)]))
    try await settle(hosting)
    #expect(
      abs(
        collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - retiredOffset)
        < 1)
    hosting.rootView = content()
    try await settle(hosting)
    let remounted = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    #expect(
      abs(collectionOffset(remounted, horizontal: horizontal, rightToLeft: rightToLeft) - 786) < 1)
    #expect(abs(model.viewport.leadingOffset - 786) < 1)
  }

  @Test(arguments: [false, true], [false, true])
  @MainActor func firstMeasurementRetainsConfiguredInitialAnchor(
    horizontal: Bool, rightToLeft: Bool
  ) async throws {
    let model = try CollectionHarness(horizontal: horizontal, initialOffset: 607.5)
    let hosting = NSHostingView(
      rootView: HarnessView(model: model)
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
        .onAppear {
          model.viewport.replace(
            try! CollectionGeometry(
              count: 10000, defaultExtent: 40,
              overrides: [CollectionExtent(index: 0, extent: 181.3)]),
            preserveMeasurementAnchor: true)
        })
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - 748.8) < 1)
    #expect(abs(model.viewport.leadingOffset - 748.8) < 1)
  }

  @Test(arguments: [false, true], [false, true])
  @MainActor func axisReplacementRetainsNativeAnchor(horizontal: Bool, rightToLeft: Bool)
    async throws
  {
    let model = try CollectionHarness(horizontal: horizontal)
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    var scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: 607.5, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    model.viewport.replace(model.viewport.geometry, vertical: horizontal)
    try await settle(hosting)
    scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    #expect(
      abs(collectionOffset(scroll, horizontal: !horizontal, rightToLeft: rightToLeft) - 607.5) < 1)
    #expect(abs(model.viewport.leadingOffset - 607.5) < 1)
  }

  @Test(
    arguments: [false, true],
    [
      (false, false, 40.0, 181.3), (false, false, 426.0, 40.0),
      (true, false, 40.0, 181.3), (true, false, 426.0, 40.0),
      (true, true, 40.0, 181.3), (true, true, 426.0, 40.0),
    ])
  @MainActor func extentAnimationKeepsTrailingEdgeWhenFinishing(
    finishEarly: Bool, layout: (Bool, Bool, Double, Double)
  ) async throws {
    let (horizontal, rightToLeft, initialExtent, finalExtent) = layout
    let model = try CollectionHarness(horizontal: horizontal)
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: initialExtent)]))
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    let viewportExtent =
      horizontal ? scroll.contentView.bounds.width : scroll.contentView.bounds.height
    let start = 9999 * 40 + initialExtent - viewportExtent
    moveCollection(scroll, to: start, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - start) < 1)
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: finalExtent)]),
      timing: CollectionTiming(expandMilliseconds: 600, collapseMilliseconds: 600))
    try await Task.sleep(for: .milliseconds(40))
    if finishEarly { model.viewport.setReducedMotion(true) }
    try await Task.sleep(for: .milliseconds(finishEarly ? 120 : 700))
    try await settle(hosting)
    let expected = 9999 * 40 + finalExtent - viewportExtent
    #expect(model.viewport.geometry.extent(at: 0) == finalExtent)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - expected) < 1
    )
    #expect(abs(model.viewport.leadingOffset - expected) < 1)
  }

  @Test(arguments: [false, true])
  @MainActor func extentAnimationRetainsStationaryFractionalAnchor(horizontal: Bool) async throws {
    let model = try CollectionHarness(horizontal: horizontal)
    let hosting = NSHostingView(rootView: HarnessView(model: model))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: 607.5, horizontal: horizontal, rightToLeft: false)
    try await settle(hosting)
    let start = collectionOffset(scroll, horizontal: horizontal, rightToLeft: false)
    for extent in [181.3, 40.0, 181.3, 40.0] {
      model.viewport.replace(
        try CollectionGeometry(
          count: 10000, defaultExtent: 40,
          overrides: [CollectionExtent(index: 0, extent: extent)]),
        timing: CollectionTiming(expandMilliseconds: 240, collapseMilliseconds: 190))
      try await Task.sleep(for: .milliseconds(320))
      try await settle(hosting)
      let expected = start + extent - 40
      #expect(
        abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: false) - expected) < 1)
      #expect(abs(model.viewport.leadingOffset - expected) < 1)
    }
  }

  @Test(
    arguments: [-6.0, -0.5, 0, 0.5, 6],
    [
      (false, false, 200.0), (false, true, 200.0), (true, false, 200.0),
      (true, true, 200.0), (false, false, 600.0), (true, true, 600.0),
    ])
  @MainActor func extentAnimationPreservesPhaseLessNativeScroll(
    delta: Double, layout: (Bool, Bool, Double)
  )
    async throws
  {
    let (horizontal, rightToLeft, initialOffset) = layout
    let model = try CollectionHarness(horizontal: horizontal)
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 426)]))
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: initialOffset, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    #expect(abs(model.viewport.leadingOffset - initialOffset) < 1)
    #expect(!model.viewport.userIsScrolling)

    // Inside row zero no correction is required; beyond it the extent
    // change contributes eight points. Preserve native input in both cases.
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 434)]),
      timing: CollectionTiming(expandMilliseconds: 600, collapseMilliseconds: 600))
    try await Task.sleep(for: .milliseconds(40))
    #expect(model.viewport.geometry.extent(at: 0) < 434)
    for _ in 0..<6 {
      let current = collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft)
      moveCollection(
        scroll, to: current + delta, horizontal: horizontal, rightToLeft: rightToLeft)
      hosting.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(30))
    }
    try await Task.sleep(for: .milliseconds(650))
    try await settle(hosting)
    let expected = initialOffset + delta * 6 + (initialOffset >= 426 ? 8 : 0)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - expected) < 1
    )
    #expect(abs(model.viewport.leadingOffset - expected) < 1)
    #expect(model.viewport.geometry.extent(at: 0) == 434)
  }

  @Test(
    arguments: [-6.0, 6],
    [(false, false, 600.0), (true, false, 600.0), (true, true, 600.0)])
  @MainActor func extentRetargetPreservesUnobservedNativeTravel(
    delta: Double, layout: (Bool, Bool, Double)
  )
    async throws
  {
    let (horizontal, rightToLeft, initialOffset) = layout
    let model = try CollectionHarness(horizontal: horizontal)
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 426)]))
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: initialOffset, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    #expect(abs(model.viewport.leadingOffset - initialOffset) < 1)
    #expect(!model.viewport.userIsScrolling)

    // Inside row zero no correction is required; beyond it the extent
    // change contributes eight points. Preserve native input in both cases.
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 434)]),
      timing: CollectionTiming(expandMilliseconds: 600, collapseMilliseconds: 600))
    try await Task.sleep(for: .milliseconds(40))
    #expect(model.viewport.geometry.extent(at: 0) < 434)
    let current = collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft)
    moveCollection(scroll, to: current + delta, horizontal: horizontal, rightToLeft: rightToLeft)
    // Retarget before SwiftUI delivers a geometry observation for this move.
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 450)]),
      timing: CollectionTiming(expandMilliseconds: 600, collapseMilliseconds: 600))
    try await Task.sleep(for: .milliseconds(650))
    try await settle(hosting)
    let expected = initialOffset + delta + 24
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - expected) < 1
    )
    #expect(abs(model.viewport.leadingOffset - expected) < 1)
    #expect(model.viewport.geometry.extent(at: 0) == 450)
  }

  @Test(
    arguments: [-6.0, 6],
    [(false, false, 600.0), (true, false, 600.0), (true, true, 600.0)])
  @MainActor func measurementAfterAnimationPreservesNativeTravel(
    delta: Double, layout: (Bool, Bool, Double)
  )
    async throws
  {
    let (horizontal, rightToLeft, initialOffset) = layout
    let model = try CollectionHarness(horizontal: horizontal)
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 426)]))
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: initialOffset, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    #expect(abs(model.viewport.leadingOffset - initialOffset) < 1)
    #expect(!model.viewport.userIsScrolling)

    // Inside row zero no correction is required; beyond it the extent
    // change contributes eight points. Preserve native input in both cases.
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 362)]),
      timing: CollectionTiming(expandMilliseconds: 200, collapseMilliseconds: 200))
    try await Task.sleep(for: .milliseconds(300))
    try await settle(hosting)
    #expect(model.viewport.geometry.extent(at: 0) == 362)
    #expect(
      abs(
        collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft)
          - (initialOffset - 64)) < 1)
    for step in 0..<12 {
      let event = try #require(
        CGEvent(
          scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
          wheel1: horizontal ? 0 : Int32(-delta),
          wheel2: horizontal ? Int32(rightToLeft ? delta : -delta) : 0,
          wheel3: 0))
      scroll.scrollWheel(with: try #require(NSEvent(cgEvent: event)))
      if step == 3 {
        model.rows = model.viewport.requestedWindow
        model.viewport.replace(
          try CollectionGeometry(
            count: 10000, defaultExtent: 40,
            overrides: [CollectionExtent(index: 0, extent: 434)]),
          preserveMeasurementAnchor: true)
      }
      hosting.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(16))
    }
    try await settle(hosting)
    let expected = initialOffset + delta * 12 + 8
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - expected) < 1
    )
    #expect(abs(model.viewport.leadingOffset - expected) < 1)
    #expect(model.viewport.geometry.extent(at: 0) == 434)
  }

  @Test(
    arguments: [-6.0, 6],
    [
      (false, false, 200.0), (false, false, 600.0),
      (true, true, 200.0), (true, true, 600.0),
    ])
  @MainActor func extentAnimationPreservesNativeWheelScroll(
    delta: Double, layout: (Bool, Bool, Double)
  )
    async throws
  {
    let (horizontal, rightToLeft, initialOffset) = layout
    let model = try CollectionHarness(horizontal: horizontal)
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 426)]))
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: initialOffset, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    #expect(abs(model.viewport.leadingOffset - initialOffset) < 1)
    #expect(!model.viewport.userIsScrolling)

    // Inside row zero no correction is required; beyond it the extent
    // change contributes eight points. Preserve native input in both cases.
    model.viewport.replace(
      try CollectionGeometry(
        count: 10000, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 434)]),
      timing: CollectionTiming(expandMilliseconds: 600, collapseMilliseconds: 600))
    try await Task.sleep(for: .milliseconds(40))
    #expect(model.viewport.geometry.extent(at: 0) < 434)
    for _ in 0..<6 {
      let event = try #require(
        CGEvent(
          scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
          wheel1: horizontal ? 0 : Int32(-delta),
          wheel2: horizontal ? Int32(rightToLeft ? delta : -delta) : 0,
          wheel3: 0))
      scroll.scrollWheel(with: try #require(NSEvent(cgEvent: event)))
      hosting.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(30))
    }
    try await Task.sleep(for: .milliseconds(650))
    try await settle(hosting)
    let expected = initialOffset + delta * 6 + (initialOffset >= 426 ? 8 : 0)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - expected) < 1
    )
    #expect(abs(model.viewport.leadingOffset - expected) < 1)
    #expect(model.viewport.geometry.extent(at: 0) == 434)
  }

  @Test(arguments: ["append", "tail-measurement", "pending-correction"], [false, true])
  @MainActor func measuredReplacementAllowsNativeReturnToTop(change: String, horizontal: Bool)
    async throws
  {
    let model = try CollectionHarness(horizontal: horizontal)
    let hosting = NSHostingView(rootView: HarnessView(model: model))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 420),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: 4007, horizontal: horizontal, rightToLeft: false)
    try await settle(hosting)
    #expect(abs(model.viewport.leadingOffset - 4007) < 1)
    model.rows = model.viewport.requestedWindow
    try await settle(hosting)

    let overrides: [CollectionExtent]
    if change == "pending-correction" {
      overrides = [CollectionExtent(index: 10, extent: 180)]
      model.viewport.replace(
        try CollectionGeometry(count: 10000, defaultExtent: 40, overrides: overrides),
        preserveMeasurementAnchor: true)
      // Append before native layout acknowledges the correction above the anchor.
    } else {
      overrides = change == "tail-measurement" ? [CollectionExtent(index: 200, extent: 180)] : []
    }
    model.viewport.replace(
      try CollectionGeometry(
        count: change == "tail-measurement" ? 10000 : 10020,
        defaultExtent: 40, overrides: overrides), preserveMeasurementAnchor: true)
    try await settle(hosting)
    let expectedOffset = change == "pending-correction" ? 4147.0 : 4007.0
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: false) - expectedOffset) < 1
    )
    #expect(abs(model.viewport.leadingOffset - expectedOffset) < 1)

    // Discrete native scrolling need not produce an interacting phase.
    #expect(!model.viewport.userIsScrolling)
    moveCollection(scroll, to: 0, horizontal: horizontal, rightToLeft: false)
    try await settle(hosting)
    #expect(abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: false)) < 1)
    #expect(abs(model.viewport.leadingOffset) < 1)
    #expect(model.viewport.requestedWindow.lowerBound == 0)
    model.rows = model.viewport.requestedWindow
    try await settle(hosting)
    let first = try #require(nativeDescendants(hosting, RowMarkerView.self).first { $0.index == 0 })
    #expect(abs(rowOffset(first, in: scroll, horizontal: horizontal, rightToLeft: false)) < 1)
  }

  @Test(arguments: [false, true], [false, true]) @MainActor
  func rapidJumpRequestsOnlyVisibleRowsAndPlacesLoadedContentAtExactOffsets(
    horizontal: Bool, rightToLeft: Bool
  )
    async throws
  {
    let model = try CollectionHarness(horizontal: horizontal)
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: NSRect(
        x: 0, y: 0, width: horizontal ? 600 : 420, height: horizontal ? 420 : 600),
      styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    let document = try #require(scroll.documentView)
    #expect(abs((horizontal ? document.frame.width : document.frame.height) - 400000) < 1)
    #expect(model.viewport.visibleRange == 0..<15 && model.viewport.requestedWindow == 0..<19)
    moveCollection(scroll, to: 300000, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    #expect(model.viewport.visibleRange == 7500..<7515)
    #expect(model.viewport.requestedWindow == 7496..<7519)
    model.rows = model.viewport.requestedWindow
    try await settle(hosting)
    let markers = nativeDescendants(hosting, RowMarkerView.self)
    #expect(markers.count == 23)
    let row = try #require(markers.first { $0.index == 7500 })
    #expect(
      abs(rowOffset(row, in: scroll, horizontal: horizontal, rightToLeft: rightToLeft) - 300000) < 1
    )
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - 300000) < 1)
    #expect(abs((horizontal ? document.frame.width : document.frame.height) - 400000) < 1)
  }

  @Test(arguments: [false, true], [false, true]) @MainActor
  func nativeExtentAnimationPreservesAnchorReversesAndHonorsReducedMotion(
    horizontal: Bool, rightToLeft: Bool
  )
    async throws
  {
    let model = try CollectionHarness(horizontal: horizontal)
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: NSRect(
        x: 0, y: 0, width: horizontal ? 600 : 420, height: horizontal ? 420 : 600),
      styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: 4007, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    model.rows = model.viewport.requestedWindow
    try await settle(hosting)
    let anchored = try #require(
      nativeDescendants(hosting, RowMarkerView.self).first { $0.index == 100 })
    let expanded = try CollectionGeometry(
      count: 10000, defaultExtent: 40, overrides: [CollectionExtent(index: 10, extent: 200)])
    model.viewport.replace(
      expanded, timing: CollectionTiming(expandMilliseconds: 2000, collapseMilliseconds: 400))
    try await settle(hosting)
    let intermediate = model.viewport.geometry.extent(at: 10)
    #expect(intermediate > 40 && intermediate < 200)
    #expect(
      abs(
        rowOffset(anchored, in: scroll, horizontal: horizontal, rightToLeft: rightToLeft)
          - collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) + 7) < 1)
    #expect(nativeDescendants(hosting, RowMarkerView.self).first { $0.index == 100 } === anchored)
    model.viewport.replace(
      try CollectionGeometry(count: 10000, defaultExtent: 40),
      timing: CollectionTiming(expandMilliseconds: 2000, collapseMilliseconds: 400))
    try await settle(hosting)
    #expect(model.viewport.geometry.extent(at: 10) < intermediate)
    #expect(model.viewport.geometry.extent(at: 10) > 40)
    try await Task.sleep(for: .milliseconds(450))
    try await settle(hosting)
    #expect(model.viewport.geometry.extent(at: 10) == 40)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - 4007) < 1)
    model.viewport.replace(
      expanded, timing: CollectionTiming(expandMilliseconds: 2000, collapseMilliseconds: 400))
    try await settle(hosting)
    model.viewport.setReducedMotion(true)
    try await settle(hosting)
    #expect(model.viewport.geometry == expanded)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - 4167) < 1)
    model.viewport.setReducedMotion(false)
    try await settle(hosting)
    let compact = try CollectionGeometry(count: 10000, defaultExtent: 40)
    model.viewport.replace(
      compact, timing: CollectionTiming(expandMilliseconds: 2000, collapseMilliseconds: 2000))
    try await settle(hosting)
    window.contentView = nil
    try await Task.sleep(for: .milliseconds(100))
    #expect(!model.viewport.isMounted)
    #expect(model.viewport.geometry == compact)
  }

  @Test(arguments: [false, true], [false, true]) @MainActor
  func expansionPagingResizeAndAnchorRelocationKeepTheViewportStable(
    horizontal: Bool, rightToLeft: Bool
  ) async throws {
    let model = try CollectionHarness(horizontal: horizontal)
    let hosting = NSHostingView(
      rootView: HarnessView(model: model).environment(
        \.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
    let window = NSWindow(
      contentRect: NSRect(
        x: 0, y: 0, width: horizontal ? 600 : 420, height: horizontal ? 420 : 600),
      styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    try await settle(hosting)
    let scroll = try #require(nativeDescendants(hosting, NSScrollView.self).first)
    moveCollection(scroll, to: 4007, horizontal: horizontal, rightToLeft: rightToLeft)
    try await settle(hosting)
    model.rows = model.viewport.requestedWindow
    try await settle(hosting)
    let row = try #require(nativeDescendants(hosting, RowMarkerView.self).first { $0.index == 100 })
    let expanded = try CollectionGeometry(
      count: 10000, defaultExtent: 40,
      overrides: [CollectionExtent(index: 10, extent: 180)])
    model.viewport.replace(expanded)
    try await settle(hosting)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - 4147) < 1)
    #expect(nativeDescendants(hosting, RowMarkerView.self).first { $0.index == 100 } === row)
    model.viewport.replace(
      try CollectionGeometry(count: 10020, defaultExtent: 40, overrides: expanded.overrides))
    try await settle(hosting)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - 4147) < 1)
    window.setContentSize(NSSize(width: horizontal ? 800 : 600, height: horizontal ? 600 : 800))
    try await settle(hosting)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - 4147) < 1)
    #expect(model.viewport.visibleRange == 100..<121)
    #expect(model.viewport.requestedWindow.count == 29)
    // The owner resolves stable-key movement before replacing metric data.
    model.viewport.replace(
      try CollectionGeometry(count: 10019, defaultExtent: 40, overrides: expanded.overrides),
      relocatedAnchorIndex: 99)
    try await settle(hosting)
    #expect(
      abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft) - 4107) < 1)
    model.rows = 0..<0
    model.viewport.replace(try CollectionGeometry(count: 0, defaultExtent: 40))
    try await settle(hosting)
    #expect(model.viewport.visibleRange.isEmpty && model.viewport.requestedWindow.isEmpty)
    #expect(abs(collectionOffset(scroll, horizontal: horizontal, rightToLeft: rightToLeft)) < 1)
  }
}

@MainActor struct CollectionPositionRefinementTests {
  @Test func equalAnchorRefinementDoesNotIssueAnotherScrollCommand() throws {
    let viewport = try CollectionViewport(
      geometry: CollectionGeometry(count: 10, defaultExtent: 40))
    viewport.observe(CGRect(x: 0, y: 0, width: 300, height: 100))
    let publications = Mutex(0)
    withObservationTracking {
      _ = viewport.position
    } onChange: {
      publications.withLock { $0 += 1 }
    }
    viewport.replace(
      try CollectionGeometry(
        count: 10, defaultExtent: 40,
        overrides: [CollectionExtent(index: 5, extent: 80)]), preserveMeasurementAnchor: true)
    #expect(publications.withLock { $0 } == 0)
    #expect(viewport.geometry.extent(at: 5) == 80)
    viewport.userIsScrolling = true
    viewport.observe(CGRect(x: 0, y: 80, width: 300, height: 100))
    viewport.userIsScrolling = false
    viewport.replace(
      try CollectionGeometry(
        count: 10, defaultExtent: 40,
        overrides: [CollectionExtent(index: 0, extent: 80)]), preserveMeasurementAnchor: true)
    #expect(publications.withLock { $0 } == 1)
    #expect(viewport.leadingOffset == 120)
  }
}
