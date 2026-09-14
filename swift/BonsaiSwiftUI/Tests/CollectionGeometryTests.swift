import Testing

@testable import BonsaiSwiftUI

struct CollectionGeometryTests {
  @Test func sparseExtentsPreserveExactBoundariesAndBoundTheWindow() throws {
    let geometry = try CollectionGeometry(
      count: 10000, defaultExtent: 40,
      overrides: [
        CollectionExtent(index: 2, extent: 180), CollectionExtent(index: 9999, extent: 80),
      ])
    #expect(geometry.totalExtent == 400180)
    #expect(geometry.offset(at: 2) == 80 && geometry.offset(at: 3) == 260)
    #expect(geometry.extent(at: 2) == 180 && geometry.extent(at: 3) == 40)
    #expect(geometry.visibleRange(offset: 80, extent: 180) == 2..<3)
    #expect(geometry.visibleRange(offset: 79, extent: 182) == 1..<4)
    #expect(geometry.window(offset: 300140, extent: 600, overscan: 4) == 7496..<7519)
    #expect(geometry.window(offset: -100, extent: 600, overscan: 4) == 0..<13)
    #expect(geometry.visibleRange(offset: 500000, extent: 600).isEmpty)
    #expect(geometry.visibleRange(offset: 0, extent: 0).isEmpty)
  }

  @Test func metricChangesRestoreTheTopRowAndClampAfterRemoval() throws {
    let initial = try CollectionGeometry(count: 10000, defaultExtent: 40)
    let anchor = try #require(initial.anchor(at: 300007))
    #expect(anchor == CollectionAnchor(index: 7500, offset: 7))
    let expanded = try CollectionGeometry(
      count: 10000, defaultExtent: 40,
      overrides: [CollectionExtent(index: 10, extent: 180)])
    #expect(expanded.offset(for: anchor, viewportExtent: 600) == 300147)
    let shortened = try CollectionGeometry(count: 20, defaultExtent: 40)
    #expect(shortened.offset(for: anchor, viewportExtent: 600) == 200)
    let empty = try CollectionGeometry(count: 0, defaultExtent: 40)
    #expect(empty.anchor(at: 0) == nil && empty.offset(for: anchor, viewportExtent: 600) == 0)
    #expect(expanded.anchor(at: -30) == CollectionAnchor(index: 0, offset: 0))
  }

  @Test func rejectsMalformedAndUnrepresentableMetrics() throws {
    for count in [-1, Int.max] {
      #expect(throws: CollectionError.self) {
        try CollectionGeometry(count: count, defaultExtent: 40)
      }
    }
    for extent in [0.0, -1, .infinity, .nan, Double.greatestFiniteMagnitude] {
      #expect(throws: CollectionError.self) {
        try CollectionGeometry(count: 20, defaultExtent: extent)
      }
    }
    for overrides in [
      [CollectionExtent(index: 20, extent: 40)],
      [CollectionExtent(index: -1, extent: 40)],
      [CollectionExtent(index: 2, extent: 40), CollectionExtent(index: 1, extent: 40)],
      [CollectionExtent(index: 2, extent: 40), CollectionExtent(index: 2, extent: 80)],
      [CollectionExtent(index: 2, extent: .nan)],
      [CollectionExtent(index: 2, extent: 0)],
    ] {
      #expect(throws: CollectionError.self) {
        try CollectionGeometry(count: 20, defaultExtent: 40, overrides: overrides)
      }
    }
  }
}
