import SwiftUI

struct RenderProjection: Equatable, Sendable {
  private let values: [Double]

  static func decode(_ reader: inout WireReader) throws -> Self {
    Self(values: try (0..<9).map { _ in try reader.finiteDouble() })
  }

  var native: ProjectionTransform {
    var result = ProjectionTransform()
    result.m11 = values[0]
    result.m12 = values[1]
    result.m13 = values[2]
    result.m21 = values[3]
    result.m22 = values[4]
    result.m23 = values[5]
    result.m31 = values[6]
    result.m32 = values[7]
    result.m33 = values[8]
    return result
  }
}
