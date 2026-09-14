import Foundation

/// Convert a native keyboard layout rectangle into representable physical edge occlusion.
enum NativeKeyboardOcclusion {
  static func insets(viewport: CGRect, occlusion: CGRect) throws -> NativeHostEnvironment.Insets {
    for rectangle in [viewport, occlusion] {
      guard
        [rectangle.origin.x, rectangle.origin.y, rectangle.size.width, rectangle.size.height]
          .allSatisfy(\.isFinite), rectangle.size.width >= 0, rectangle.size.height >= 0
      else { throw WireError.invalidOperation }
    }
    guard !viewport.isEmpty, !occlusion.isEmpty else { return .init() }
    let overlap = viewport.intersection(occlusion)
    guard !overlap.isNull, !overlap.isEmpty else { return .init() }
    // An inset describes a complete edge. Floating/partial-width keyboards are
    // rectangles, not edge occlusion, and must not shrink the entire application.
    if overlap.minX == viewport.minX, overlap.maxX == viewport.maxX {
      if overlap.maxY == viewport.maxY { return .init(bottom: overlap.height) }
      if overlap.minY == viewport.minY { return .init(top: overlap.height) }
    }
    if overlap.minY == viewport.minY, overlap.maxY == viewport.maxY {
      if overlap.minX == viewport.minX { return .init(left: overlap.width) }
      if overlap.maxX == viewport.maxX { return .init(right: overlap.width) }
    }
    return .init()
  }
}
