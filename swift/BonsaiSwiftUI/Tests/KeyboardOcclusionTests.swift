import Foundation
import Testing

@testable import BonsaiSwiftUI

struct KeyboardOcclusionTests {
  private let viewport = CGRect(x: 40, y: 20, width: 400, height: 800)

  @Test func dockedOcclusionUsesIntersectionInPhysicalWindowCoordinates() throws {
    let samples: [(CGRect, NativeHostEnvironment.Insets)] = [
      (CGRect(x: 0, y: 620, width: 500, height: 400), .init(bottom: 200)),
      (CGRect(x: 40, y: -40, width: 400, height: 160), .init(top: 100)),
      (CGRect(x: -20, y: 0, width: 120, height: 900), .init(left: 60)),
      (CGRect(x: 400, y: 0, width: 100, height: 900), .init(right: 40)),
      (CGRect(x: 0, y: 0, width: 500, height: 1000), .init(bottom: 800)),
    ]
    for (occlusion, expected) in samples {
      #expect(
        try NativeKeyboardOcclusion.insets(viewport: viewport, occlusion: occlusion) == expected)
    }
  }

  @Test func floatingOffscreenAndHiddenKeyboardsDoNotCreateEdgeInsets() throws {
    for occlusion in [
      CGRect.zero, CGRect(x: 40, y: 820, width: 400, height: 0),
      CGRect(x: 40, y: 900, width: 400, height: 100),
      CGRect(x: 100, y: 400, width: 260, height: 200),
      CGRect(x: 100, y: 620, width: 260, height: 200),
      CGRect(x: 40, y: 400, width: 400, height: 200),
    ] {
      #expect(
        try NativeKeyboardOcclusion.insets(viewport: viewport, occlusion: occlusion) == .init())
    }
    #expect(try NativeKeyboardOcclusion.insets(viewport: .zero, occlusion: viewport) == .init())
  }

  @Test func invalidGeometryIsRejected() {
    for rectangle in [
      CGRect(x: Double.nan, y: 0, width: 1, height: 1),
      CGRect(x: 0, y: Double.infinity, width: 1, height: 1),
      CGRect(x: 0, y: 0, width: -1, height: 1),
      CGRect(x: 0, y: 0, width: 1, height: -1),
    ] {
      #expect(throws: (any Error).self) {
        _ = try NativeKeyboardOcclusion.insets(viewport: rectangle, occlusion: viewport)
      }
      #expect(throws: (any Error).self) {
        _ = try NativeKeyboardOcclusion.insets(viewport: viewport, occlusion: rectangle)
      }
    }
  }
}
