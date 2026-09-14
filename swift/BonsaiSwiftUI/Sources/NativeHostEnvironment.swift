struct NativeHostEnvironment: Equatable, Sendable {
  enum Brightness: UInt8, Sendable { case light, dark }
  enum Orientation: UInt8, Sendable { case portrait, landscape }
  enum Platform: String, Sendable { case ios, macos }
  struct Insets: Equatable, Sendable {
    var left: Double = 0
    var top: Double = 0
    var right: Double = 0
    var bottom: Double = 0
    var values: [Double] { [left, top, right, bottom] }
  }
  var viewportWidth: Double
  var viewportHeight: Double
  var devicePixelRatio: Double
  var textScale: Double
  var brightness: Brightness
  var platform: Platform
  var locale: String
  var safeArea: Insets
  var keyboardInsets: Insets
  var accessibleNavigation: Bool
  var boldText: Bool
  var invertColors: Bool
  var disableAnimations: Bool
  var reducedMotion: Bool
  var highContrast: Bool
  var orientation: Orientation
  var pointerKinds: UInt32

  func encode(into writer: inout WireWriter) throws {
    let dimensions = [viewportWidth, viewportHeight, devicePixelRatio, textScale]
    guard dimensions.allSatisfy(\.isFinite), viewportWidth >= 0, viewportHeight >= 0,
      devicePixelRatio > 0, textScale > 0,
      safeArea.values.allSatisfy(\.isFinite), keyboardInsets.values.allSatisfy(\.isFinite)
    else { throw WireError.invalidHeader }
    for value in dimensions { writer.integer(value.bitPattern) }
    writer.integer(brightness.rawValue)
    try writer.string(platform.rawValue)
    try writer.string(locale)
    for value in safeArea.values + keyboardInsets.values { writer.integer(value.bitPattern) }
    for value in [
      accessibleNavigation, boldText, invertColors, disableAnimations,
      reducedMotion, highContrast,
    ] {
      writer.integer(UInt8(value ? 1 : 0))
    }
    writer.integer(orientation.rawValue)
    writer.integer(pointerKinds)
  }
}
