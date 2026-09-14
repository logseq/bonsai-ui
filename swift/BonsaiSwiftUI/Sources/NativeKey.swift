struct NativeKey: Equatable, Sendable {
  enum Action: UInt8, Sendable {
    case down = 0
    case up = 1
    case `repeat` = 2
  }
  var logical: UInt64
  var physical: UInt64
  var action: Action
  var modifiers: UInt32
}
