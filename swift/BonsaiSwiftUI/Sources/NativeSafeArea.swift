import SwiftUI

struct RenderSafeArea: Equatable, Sendable {
  let regions: Int
  let edges: Int

  static func decode(_ reader: inout WireReader) throws -> Self {
    Self(regions: try reader.choice(2), edges: try reader.choice(15))
  }

  var nativeRegions: SafeAreaRegions {
    switch regions {
    case 1: .keyboard
    case 2: .all
    default: .container
    }
  }

  var nativeEdges: Edge.Set {
    var result: Edge.Set = []
    if edges & 1 != 0 { result.insert(.leading) }
    if edges & 2 != 0 { result.insert(.top) }
    if edges & 4 != 0 { result.insert(.trailing) }
    if edges & 8 != 0 { result.insert(.bottom) }
    return result
  }
}
