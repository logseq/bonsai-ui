import SwiftUI

struct RenderSurface: Equatable {
  let mode: Int
  let presentationBackground: Bool
  let colors: [UInt32]
  let radius: Double
  let shadowRadius: Double
  let shadowX: Double
  let shadowY: Double
  let borderWidth: Double
  let opacity: Double
  let shadowColor: UInt32
  let borderColor: UInt32

  static func decode(_ data: Data) throws -> Self {
    var reader = WireReader(data)
    let mode = try reader.choice(5)
    let count = Int(try reader.integer(UInt8.self))
    let presentation = try reader.flag()
    guard try reader.integer(UInt8.self) == 0,
      (mode == 1 || mode == 2) ? (2...16).contains(count) : count == 1
    else { throw TreeError.invalidProperties }
    let values = try (0..<6).map { _ in Double(bitPattern: try reader.integer(UInt64.self)) }
    guard values.allSatisfy(\.isFinite), values[0] >= 0, values[1] >= 0, values[4] >= 0,
      (0...1).contains(values[5])
    else { throw TreeError.invalidProperties }
    let shadow = try reader.integer(UInt32.self)
    let border = try reader.integer(UInt32.self)
    let colors = try (0..<count).map { _ in try reader.integer(UInt32.self) }
    guard reader.remaining == 0 else { throw TreeError.invalidProperties }
    return Self(
      mode: mode, presentationBackground: presentation, colors: colors, radius: values[0],
      shadowRadius: values[1],
      shadowX: values[2], shadowY: values[3], borderWidth: values[4], opacity: values[5],
      shadowColor: shadow, borderColor: border)
  }
}

@MainActor enum NativeSurface {
  static var definition: NativeViewDefinition {
    BonsaiNativeViews.definition(
      version: 2, capabilities: [], decode: RenderSurface.decode,
      validateChildren: { _, count in
        guard count == 1 else { throw TreeError.invalidChildren }
      }, encodeEvent: { (event: Never) in switch event {} }, makeResource: { () },
      dispose: { _ in },
      content: { NativeSurfaceView(context: $0) })
  }
}

private struct NativeSurfaceView: View {
  let context: BonsaiNativeContext<RenderSurface, Never, Void>
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  private var p: RenderSurface { context.properties }
  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: p.radius, style: .continuous)
  }

  private var background: some View {
    NativeSurfacePaint(properties: p, reduceTransparency: reduceTransparency)
  }

  private var content: some View {
    context.children[0]
      .background {
        background
          .overlay { shape.strokeBorder(Color(argb: p.borderColor), lineWidth: p.borderWidth) }
          .shadow(
            color: Color(argb: p.shadowColor), radius: p.shadowRadius, x: p.shadowX, y: p.shadowY
          )
          .allowsHitTesting(false).accessibilityHidden(true)
      }
  }
  @ViewBuilder var body: some View {
    if p.presentationBackground {
      #if os(iOS)
        context.children[0]
          .background {
            background.overlay {
              shape.strokeBorder(Color(argb: p.borderColor), lineWidth: p.borderWidth)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false).accessibilityHidden(true)
          }
          .presentationBackground(Color.clear)
          .presentationCornerRadius(p.radius)
      #else
        content
      #endif
    } else {
      content
    }
  }
}

/// The shared material paint path, with explicit accessibility input for native verification.
struct NativeSurfacePaint: View {
  let properties: RenderSurface
  let reduceTransparency: Bool
  private var p: RenderSurface { properties }
  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: p.radius, style: .continuous)
  }
  var body: some View {
    paint.opacity(reduceTransparency && p.mode >= 3 ? 1 : p.opacity)
  }
  @ViewBuilder private var paint: some View {
    switch p.mode {
    case 0: shape.fill(Color(argb: p.colors[0]))
    case 1:
      shape.fill(
        LinearGradient(
          colors: p.colors.map { Color(argb: $0) }, startPoint: .top, endPoint: .bottom))
    case 2: shape.fill(AngularGradient(colors: p.colors.map { Color(argb: $0) }, center: .center))
    default:
      if reduceTransparency {
        shape.fill(Color(argb: p.colors[0] | 0xff00_0000))
      } else {
        shape.fill(
          p.mode == 5 ? Material.ultraThin : p.mode == 3 ? Material.thin : Material.regular
        )
        .overlay { shape.fill(Color(argb: p.colors[0])) }
      }
    }
  }

}
