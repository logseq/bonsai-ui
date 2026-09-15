import Foundation

struct CollectionTiming: Equatable, Sendable {
  let expandMilliseconds: UInt32
  let collapseMilliseconds: UInt32
  static let immediate = Self(expandMilliseconds: 0, collapseMilliseconds: 0)
}

struct CollectionAnimation {
  private struct Change {
    let index: Int
    let from: Double
    let to: Double
    let duration: Double
    func extent(elapsed: Double) -> Double {
      guard duration > 0 else { return to }
      let t = min(1, max(0, elapsed / duration))
      let progress: Double
      if to > from {
        progress = 1 - pow(1 - t, 3)
      } else {
        progress = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
      }
      return from + (to - from) * progress
    }
  }
  let target: CollectionGeometry
  private let changes: [Change]
  private let started: Double
  init(
    from: CollectionGeometry, to: CollectionGeometry, timing: CollectionTiming, started: Double,
    animatedIndices: Set<Int>? = nil
  ) {
    target = to
    self.started = started
    guard from.count == to.count, from.defaultExtent == to.defaultExtent else {
      changes = []
      return
    }
    let indices = Set(from.overrides.map(\.index)).union(to.overrides.map(\.index)).sorted()
    changes = indices.map { index in
      let old = from.extent(at: index)
      let new = to.extent(at: index)
      return Change(
        index: index, from: old, to: new,
        duration: old == new || animatedIndices?.contains(index) == false
          ? 0 : Double(new > old ? timing.expandMilliseconds : timing.collapseMilliseconds) / 1000)
    }
  }
  func sample(at time: Double) -> (geometry: CollectionGeometry, finished: Bool) {
    let elapsed = max(0, time - started)
    guard changes.contains(where: { elapsed < $0.duration }) else { return (target, true) }
    let extents = changes.compactMap { change -> CollectionExtent? in
      let extent = change.extent(elapsed: elapsed)
      return extent == target.defaultExtent
        ? nil : CollectionExtent(index: change.index, extent: extent)
    }
    // Independently timed rows can exceed the coordinate bound even when both
    // endpoints fit. Resolve to the validated target if an intermediate cannot fit.
    guard
      let geometry = try? CollectionGeometry(
        count: target.count, defaultExtent: target.defaultExtent, overrides: extents)
    else {
      return (target, true)
    }
    return (geometry, false)
  }
}
