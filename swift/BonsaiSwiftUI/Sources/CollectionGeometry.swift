import Foundation

enum CollectionError: Error { case invalidMetrics, invalidWindow }

struct CollectionExtent: Equatable, Sendable {
  let index: Int
  let extent: Double
}

struct CollectionAnchor: Equatable, Sendable {
  let index: Int
  let offset: Double
}

struct CollectionGeometry: Equatable, Sendable {
  let count: Int
  let defaultExtent: Double
  let overrides: [CollectionExtent]
  private let adjustments: [Double]
  let totalExtent: Double
  init(count: Int, defaultExtent: Double, overrides: [CollectionExtent] = []) throws {
    let maximumCoordinate = 9_007_199_254_740_992.0
    guard count >= 0, count <= Int(UInt32.max), defaultExtent.isFinite,
      defaultExtent > 0, defaultExtent <= maximumCoordinate
    else { throw CollectionError.invalidMetrics }
    var previous = -1
    var cumulative: [Double] = [0]
    for extent in overrides {
      guard extent.index > previous, extent.index < count, extent.extent.isFinite,
        extent.extent > 0, extent.extent <= maximumCoordinate
      else { throw CollectionError.invalidMetrics }
      previous = extent.index
      cumulative.append(cumulative.last! + extent.extent - defaultExtent)
    }
    let total = Double(count) * defaultExtent + cumulative.last!
    guard total.isFinite, total >= 0, total <= maximumCoordinate,
      count == 0 || total > 0
    else { throw CollectionError.invalidMetrics }
    self.count = count
    self.defaultExtent = defaultExtent
    self.overrides = overrides
    adjustments = cumulative
    totalExtent = total
  }
  private func overridePosition(_ index: Int) -> Int {
    var low = 0
    var high = overrides.count
    while low < high {
      let middle = low + (high - low) / 2
      if overrides[middle].index < index { low = middle + 1 } else { high = middle }
    }
    return low
  }
  func extent(at index: Int) -> Double {
    let position = overridePosition(index)
    return position < overrides.count && overrides[position].index == index
      ? overrides[position].extent : defaultExtent
  }
  func offset(at index: Int) -> Double {
    let index = min(count, max(0, index))
    return Double(index) * defaultExtent + adjustments[overridePosition(index)]
  }
  private func boundary(at value: Double, strictlyAfter: Bool) -> Int {
    var low = 0
    var high = count
    while low < high {
      let middle = low + (high - low) / 2
      let position = offset(at: middle)
      if position < value || (strictlyAfter && position == value) {
        low = middle + 1
      } else {
        high = middle
      }
    }
    return low
  }
  func visibleRange(offset: Double, extent: Double) -> Range<Int> {
    guard count > 0, offset.isFinite, extent.isFinite, extent > 0,
      offset < totalExtent, offset + extent > 0
    else { return 0..<0 }
    let start = max(0, offset)
    let end = min(totalExtent, offset + extent)
    let first = max(0, boundary(at: start, strictlyAfter: true) - 1)
    let last = boundary(at: end, strictlyAfter: false)
    return first..<max(first, last)
  }
  func window(offset: Double, extent: Double, overscan: Int) -> Range<Int> {
    let visible = visibleRange(offset: offset, extent: extent)
    guard !visible.isEmpty else { return visible }
    let overscan = max(0, overscan)
    let first = visible.lowerBound - min(visible.lowerBound, overscan)
    let last = visible.upperBound + min(count - visible.upperBound, overscan)
    return first..<last
  }
  func anchor(at offset: Double) -> CollectionAnchor? {
    guard count > 0, offset.isFinite else { return nil }
    let index = min(count - 1, max(0, boundary(at: max(0, offset), strictlyAfter: true) - 1))
    return CollectionAnchor(
      index: index, offset: min(extent(at: index), max(0, offset - self.offset(at: index))))
  }
  func offset(for anchor: CollectionAnchor, viewportExtent: Double) -> Double {
    guard count > 0 else { return 0 }
    let index = min(count - 1, max(0, anchor.index))
    let target = offset(at: index) + min(extent(at: index), max(0, anchor.offset))
    return min(max(0, totalExtent - max(0, viewportExtent)), target)
  }
}
