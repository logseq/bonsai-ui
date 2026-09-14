import SwiftUI

struct RenderTextSpan: Equatable, Sendable {
  let value: String
  let fontSize: Double?
  let weight: Int?
  let color: UInt32?
  let italic: Bool
  let underline: Bool
  let strikethrough: Bool

  static func decode(_ reader: inout WireReader) throws -> [Self] {
    let count = Int(try reader.integer(UInt16.self))
    var spans: [Self] = []
    for _ in 0..<count {
      spans.append(
        Self(
          value: try reader.string(), fontSize: try reader.positiveOptionalDouble(),
          weight: try reader.flag() ? reader.choice(3) : nil,
          color: try reader.flag() ? reader.integer(UInt32.self) : nil,
          italic: try reader.flag(), underline: try reader.flag(), strikethrough: try reader.flag())
      )
    }
    return spans
  }
}

struct NativeRichTextView: View {
  let spans: [RenderTextSpan]
  @Environment(\.font) private var inheritedFont
  @Environment(\.bonsaiFontFamily) private var fontFamily
  @ScaledMetric(relativeTo: .body) private var fontScale: Double = 1

  private var baseFont: Font? {
    NativeTextFont.resolve(size: nil, weight: nil, family: fontFamily, inherited: inheritedFont)
  }

  private func font(for span: RenderTextSpan) -> Font? {
    NativeTextFont.resolve(
      size: span.fontSize, weight: span.weight, italic: span.italic,
      family: fontFamily, inherited: inheritedFont, scale: fontScale)
  }

  private var attributed: AttributedString {
    var result = AttributedString()
    for span in spans {
      var run = AttributedString(span.value)
      if span.fontSize != nil || span.weight != nil || span.italic { run.font = font(for: span) }
      if let color = span.color { run.foregroundColor = Color(argb: color) }
      if span.underline { run.underlineStyle = .single }
      if span.strikethrough { run.strikethroughStyle = .single }
      result += run
    }
    return result
  }

  var body: some View { Text(attributed).font(baseFont) }
}
