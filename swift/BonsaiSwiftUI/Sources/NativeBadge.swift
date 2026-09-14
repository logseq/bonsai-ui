import SwiftUI

struct RenderBadge: Equatable, Sendable {
  let count: UInt64?
  let alignment: Int
  let visible: Bool

  static func decode(_ reader: inout WireReader) throws -> Self {
    let count = try reader.flag() ? reader.integer(UInt64.self) : nil
    guard count == nil || count! <= UInt64(Int64.max) else { throw TreeError.invalidProperties }
    return Self(count: count, alignment: try reader.choice(2), visible: try reader.flag())
  }
}

struct NativeBadge<Content: View>: View {
  let properties: RenderBadge
  let content: Content
  var body: some View {
    content.overlay(alignment: nativeAlignment(properties.alignment)) {
      decoration
        .opacity(properties.visible ? 1 : 0)
        .alignmentGuide(.top) { $0.height / 2 }
        .alignmentGuide(.leading) { $0.width / 2 }
        .alignmentGuide(.trailing) { $0.width / 2 }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }

  private var decoration: AnyView {
    if let count = properties.count {
      return AnyView(
        Text(String(count)).font(.caption2.weight(.semibold))
          .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
          .background(.red, in: Capsule()).fixedSize())
    }
    return AnyView(Circle().fill(.red).frame(width: 8, height: 8))
  }
}
