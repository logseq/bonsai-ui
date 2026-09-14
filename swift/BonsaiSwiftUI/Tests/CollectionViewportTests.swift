import AppKit
import Observation
import SwiftUI
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
  init(horizontal: Bool = false) throws {
    viewport = try CollectionViewport(
      geometry: CollectionGeometry(count: 10000, defaultExtent: 40), vertical: !horizontal)
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
