import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

struct CollectionAnimationTests {
  @Test func sparseTransitionsInterpolateIndependentlyAndRetargetFromDisplayedHeights() throws {
    let compact = try CollectionGeometry(count: 10000, defaultExtent: 40)
    let expanded = try CollectionGeometry(
      count: 10000, defaultExtent: 40, overrides: [CollectionExtent(index: 10, extent: 200)])
    let timing = CollectionTiming(expandMilliseconds: 240, collapseMilliseconds: 190)
    let first = CollectionAnimation(from: compact, to: expanded, timing: timing, started: 10)
    let middle = first.sample(at: 10.12)
    #expect(abs(middle.geometry.extent(at: 10) - 180) < 0.001)
    #expect(!middle.finished)
    #expect(first.sample(at: 11).geometry == expanded && first.sample(at: 11).finished)
    let switched = try CollectionGeometry(
      count: 10000, defaultExtent: 40, overrides: [CollectionExtent(index: 15, extent: 120)])
    let second = CollectionAnimation(
      from: middle.geometry, to: switched, timing: timing, started: 20)
    #expect(second.sample(at: 20).geometry == middle.geometry)
    let crossing = second.sample(at: 20.095)
    #expect(abs(crossing.geometry.extent(at: 10) - 110) < 0.001)
    #expect(crossing.geometry.extent(at: 15) > 40 && crossing.geometry.extent(at: 15) < 120)
    #expect(!second.sample(at: 20.19).finished)
    #expect(second.sample(at: 21).geometry == switched)
    #expect(second.sample(at: 21).finished)
  }

  @Test func zeroDurationUnchangedAndStructuralUpdatesResolveImmediately() throws {
    let compact = try CollectionGeometry(count: 10, defaultExtent: 40)
    let expanded = try CollectionGeometry(
      count: 10, defaultExtent: 40, overrides: [CollectionExtent(index: 2, extent: 140)])
    for (target, timing) in [
      (expanded, CollectionTiming(expandMilliseconds: 0, collapseMilliseconds: 0)),
      (compact, CollectionTiming(expandMilliseconds: 240, collapseMilliseconds: 190)),
      (
        try CollectionGeometry(count: 11, defaultExtent: 40),
        CollectionTiming(expandMilliseconds: 240, collapseMilliseconds: 190)
      ),
      (
        try CollectionGeometry(count: 10, defaultExtent: 50),
        CollectionTiming(expandMilliseconds: 240, collapseMilliseconds: 190)
      ),
    ] {
      let sample = CollectionAnimation(from: compact, to: target, timing: timing, started: 0)
        .sample(at: 0)
      #expect(sample.finished && sample.geometry == target)
    }
  }
}
