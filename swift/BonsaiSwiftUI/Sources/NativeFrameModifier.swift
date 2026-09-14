import SwiftUI

enum FrameLimit: Equatable, Sendable {
  case points(Double)
  case fill

  var value: Double {
    switch self {
    case .points(let value): value
    case .fill: .infinity
    }
  }
}

struct RenderFrame: Equatable, Sendable {
  let width: Double?
  let height: Double?
  let minWidth: Double?
  let idealWidth: Double?
  let maxWidth: FrameLimit?
  let minHeight: Double?
  let idealHeight: Double?
  let maxHeight: FrameLimit?
  let alignment: Int

  private static func maximum(_ reader: inout WireReader) throws -> FrameLimit? {
    switch try reader.choice(2) {
    case 0: return nil
    case 2: return .fill
    default:
      let value = try reader.finiteDouble()
      guard value >= 0 else { throw TreeError.invalidProperties }
      return .points(value)
    }
  }

  private static func validateAxis(
    _ fixed: Double?, _ minimum: Double?, _ ideal: Double?, _ maximum: FrameLimit?
  ) throws {
    guard fixed == nil || (minimum == nil && ideal == nil && maximum == nil)
    else { throw TreeError.invalidProperties }
    for (lower, upper) in [(minimum, ideal), (minimum, maximum?.value), (ideal, maximum?.value)] {
      if let lower, let upper, lower > upper { throw TreeError.invalidProperties }
    }
  }

  static func decode(_ reader: inout WireReader) throws -> RenderFrame {
    let width = try reader.nonnegativeOptionalDouble()
    let height = try reader.nonnegativeOptionalDouble()
    let minWidth = try reader.nonnegativeOptionalDouble()
    let idealWidth = try reader.nonnegativeOptionalDouble()
    let maxWidth = try maximum(&reader)
    let minHeight = try reader.nonnegativeOptionalDouble()
    let idealHeight = try reader.nonnegativeOptionalDouble()
    let maxHeight = try maximum(&reader)
    let alignment = try reader.choice(8)
    try validateAxis(width, minWidth, idealWidth, maxWidth)
    try validateAxis(height, minHeight, idealHeight, maxHeight)
    return RenderFrame(
      width: width, height: height, minWidth: minWidth,
      idealWidth: idealWidth, maxWidth: maxWidth, minHeight: minHeight,
      idealHeight: idealHeight, maxHeight: maxHeight, alignment: alignment)
  }
}

struct NativeFrameModifier: ViewModifier {
  let frame: RenderFrame

  private var alignment: Alignment {
    nativeAlignment(frame.alignment)
  }

  func body(content: Content) -> AnyView {
    var view = AnyView(content)
    if frame.width != nil || frame.height != nil {
      view = AnyView(
        view.frame(
          width: frame.width.map { CGFloat($0) }, height: frame.height.map { CGFloat($0) },
          alignment: alignment))
    }
    if frame.minWidth != nil || frame.idealWidth != nil || frame.maxWidth != nil
      || frame.minHeight != nil || frame.idealHeight != nil || frame.maxHeight != nil
    {
      view = AnyView(
        view.frame(
          minWidth: frame.minWidth.map { CGFloat($0) },
          idealWidth: frame.idealWidth.map { CGFloat($0) },
          maxWidth: frame.maxWidth.map { CGFloat($0.value) },
          minHeight: frame.minHeight.map { CGFloat($0) },
          idealHeight: frame.idealHeight.map { CGFloat($0) },
          maxHeight: frame.maxHeight.map { CGFloat($0.value) }, alignment: alignment))
    }
    return view
  }
}
