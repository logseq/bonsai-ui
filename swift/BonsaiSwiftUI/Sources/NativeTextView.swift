import SwiftUI

@MainActor enum NativeTextFont {
  static func resolve(
    size: Double?, weight: Int?, italic: Bool = false, family: String?, inherited: Font?,
    scale: Double = 1
  ) -> Font? {
    guard size != nil || weight != nil || italic || family != nil else { return inherited }
    var font = inherited ?? .body
    if let family {
      #if os(macOS)
        let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
      #else
        let bodySize = UIFont.preferredFont(
          forTextStyle: .body,
          compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
      #endif
      font = .custom(family, size: size ?? bodySize, relativeTo: .body)
    } else if let size {
      font = .system(size: size * scale)
    }
    if let weight { font = font.weight([.regular, .medium, .semibold, .bold][weight]) }
    if italic { font = font.italic() }
    return font
  }
}

struct NativeTextView: View {
  let text: RenderText
  @Environment(\.bonsaiDefaults) private var defaults
  @Environment(\.legibilityWeight) private var legibilityWeight
  @Environment(\.font) private var inheritedFont
  @Environment(\.lineSpacing) private var inheritedSpacing
  @Environment(\.bonsaiFontFamily) private var fontFamily
  @ScaledMetric(relativeTo: .body) private var fontScale: Double = 1

  private var role: Int {
    let selected = text.style?.role ?? 8
    return selected == 8 ? defaults.defaultTextRole() : selected
  }
  private var styled: some View {
    Text(verbatim: text.value)
      .font(
        NativeTextFont.resolve(
          size: text.style?.fontSize
            ?? (inheritedFont == nil || role != 0
              ? defaults.textSize(role) : nil),
          weight: legibilityWeight == .bold
            ? 3 : (text.style?.weight ?? defaults.textWeight(role)),
          italic: text.style?.italic ?? defaults.textItalic(role),
          family: fontFamily, inherited: inheritedFont, scale: fontScale)
      )
      .multilineTextAlignment(
        text.alignment == 1 ? .center : text.alignment == 2 ? .trailing : .leading
      )
      .lineLimit(text.lineLimit)
      .lineSpacing(text.style?.lineSpacing ?? inheritedSpacing)
      .truncationMode([.tail, .head, .middle][text.truncation])
  }

  @ViewBuilder var body: some View {
    if let argb = text.style?.argb {
      styled.foregroundStyle(Color(argb: argb))
    } else if let role = text.style?.foreground {
      styled.foregroundStyle(defaults.color(role))
    } else if let foreground = defaults.textForeground(role) {
      styled.foregroundStyle(defaults.color(foreground))
    } else {
      styled
    }
  }
}
