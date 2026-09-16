import SwiftUI

private struct BonsaiFontFamilyKey: EnvironmentKey {
  static let defaultValue: String? = nil
}

extension EnvironmentValues {
  var bonsaiFontFamily: String? {
    get { self[BonsaiFontFamilyKey.self] }
    set { self[BonsaiFontFamilyKey.self] = newValue }
  }
}

struct SwiftUIEnvironmentModifier: ViewModifier {
  let values: ViewEnvironment
  @Environment(\.colorScheme) private var inheritedScheme
  @Environment(\.bonsaiFontFamily) private var inheritedFont

  @Environment(\.controlSize) private var inheritedControlSize
  @Environment(\.bonsaiDefaults) private var inheritedDefaults
  @Environment(\.bonsaiTint) private var inheritedTint

  private var controlSize: ControlSize {
    switch values.controlSize {
    case 0: .mini
    case 1: .small
    case 3: .large
    case 4: .extraLarge
    case 2: .regular
    default: inheritedControlSize
    }
  }

  func body(content: Content) -> some View {
    let defaults = values.defaults.inheriting(inheritedDefaults)
    let tint = values.tint.map { Color(argb: $0) } ?? inheritedTint
    return
      content
      .environment(
        \.colorScheme, values.mode == 1 ? .light : values.mode == 2 ? .dark : inheritedScheme
      )
      .environment(\.bonsaiFontFamily, values.fontFamily ?? inheritedFont)
      .environment(\.bonsaiDefaults, defaults)
      .environment(\.bonsaiTint, tint)
      .foregroundStyle(defaults.color(defaults.defaultForeground()))
      .tint(tint)
      .controlSize(controlSize)
  }

}

extension Color {
  init(argb: UInt32) {
    self.init(
      .sRGB, red: Double((argb >> 16) & 255) / 255,
      green: Double((argb >> 8) & 255) / 255,
      blue: Double(argb & 255) / 255, opacity: Double(argb >> 24) / 255)
  }
}
