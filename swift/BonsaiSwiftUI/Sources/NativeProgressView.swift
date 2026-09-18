import SwiftUI

struct RenderProgress: Equatable, Sendable {
  let value: Double?
  let style: Int

  static func decode(_ reader: inout WireReader) throws -> Self {
    let value = try reader.flag() ? reader.finiteDouble() : nil
    if let value, !(0...1).contains(value) { throw TreeError.invalidProperties }
    let style = try reader.choice(2)
    guard !(style == 0 && value == nil), !(style == 1 && value != nil) else {
      throw TreeError.invalidProperties
    }
    return Self(value: value, style: style)
  }
}

struct NativeProgressView: View {
  let properties: RenderProgress
  var body: some View {
    indicator.accessibilityValue(
      Text(properties.value ?? 0, format: .percent.precision(.fractionLength(0))),
      isEnabled: properties.value != nil)
  }
  @ViewBuilder private var indicator: some View {
    switch properties.style {
    case 0: ProgressView(value: properties.value, total: 1).progressViewStyle(.linear)
    case 1: ProgressView().progressViewStyle(.circular)
    default: ProgressView(value: properties.value, total: 1).progressViewStyle(.automatic)
    }
  }
}
