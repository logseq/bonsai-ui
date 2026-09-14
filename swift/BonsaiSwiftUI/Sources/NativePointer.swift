import Foundation

struct NativePointer: Equatable, Sendable {
  enum Kind: UInt8, Sendable {
    case mouse = 0
    case touch = 1
    case stylus = 2
    case invertedStylus = 3
    case trackpad = 4
    case unknown = 5
  }

  var id: UInt64
  var localX: Double
  var localY: Double
  var globalX: Double
  var globalY: Double
  var kind: Kind
  var buttons: UInt32

  var isValid: Bool {
    id <= UInt64(Int64.max) && [localX, localY, globalX, globalY].allSatisfy(\.isFinite)
  }
}

struct NativeTap: Equatable, Sendable {
  var localX: Double
  var localY: Double
  var globalX: Double
  var globalY: Double
  var kind: NativePointer.Kind

  var isValid: Bool {
    [localX, localY, globalX, globalY].allSatisfy(\.isFinite)
  }
}
