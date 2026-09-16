import SwiftUI

struct RenderSurface: Equatable {
  var mode: Int
  var presentationBackground: Bool
  var colors: [UInt32]
  var radius: Double
  var shadowRadius: Double
  var shadowX: Double
  var shadowY: Double
  var borderWidth: Double
  var opacity: Double
  var shadowColor: UInt32
  var borderColor: UInt32

  var recipe = 0
  var overrideMask = 511
  var capsule = false
  var shapeExplicit = false
  var contentInset = false

  func resolved(_ defaults: SharedUIDefaults, scheme: ColorScheme, contrast: ColorSchemeContrast)
    -> Self
  {
    guard recipe >= 0 else { return self }
    var result = self
    result.recipe = -1
    func omitted(_ bit: Int) -> Bool { overrideMask & (1 << bit) == 0 }
    let action = recipe == 2
    let sheet = recipe == 5
    if omitted(0) {
      result.radius =
        sheet
        ? defaults.metric(10)
        : recipe == 3
          ? defaults.metric(9)
          : recipe == 4 ? defaults.metric(7) : recipe == 6 ? defaults.metric(8) : 0
    }
    if !shapeExplicit { result.capsule = defaults.surfaceCapsule(recipe) }
    if omitted(1) { result.shadowRadius = action ? defaults.metric(12) : 0 }
    if omitted(2) { result.shadowX = action ? defaults.extraMetric(0) : 0 }
    if omitted(3) { result.shadowY = action ? defaults.metric(13) : 0 }
    if omitted(4) { result.borderWidth = action || !omitted(7) ? defaults.metric(11) : 0 }
    if omitted(5) { result.opacity = defaults.surfaceOpacity(recipe) }
    if omitted(6) { result.shadowColor = defaults.argb(7, scheme: scheme, contrast: contrast) }
    if omitted(7) { result.borderColor = defaults.argb(6, scheme: scheme, contrast: contrast) }
    if omitted(8) {
      result.mode = [0, 3, 4, 5][defaults.surfaceMaterial(recipe)]
      let role = defaults.surfaceBackground(recipe)
      let color: UInt32 = role == 9 ? 0 : defaults.argb(role, scheme: scheme, contrast: contrast)
      if let alpha = defaults.surfaceTintAlpha(recipe) {
        result.colors = [(UInt32((alpha * 255).rounded()) << 24) | (color & 0x00ff_ffff)]
      } else {
        result.colors = [color]
      }
    }
    return result
  }

  static func decode(_ data: Data) throws -> Self {
    var reader = WireReader(data)
    let mode = try reader.choice(5)
    let count = Int(try reader.integer(UInt8.self))
    let flags = try reader.choice(15)
    let recipe = try reader.choice(6)
    guard
      (mode == 1 || mode == 2) ? (2...16).contains(count) : count == 1
    else { throw TreeError.invalidProperties }
    let values = try (0..<6).map { _ in Double(bitPattern: try reader.integer(UInt64.self)) }
    guard values.allSatisfy(\.isFinite), values[0] >= 0, values[1] >= 0, values[4] >= 0,
      (0...1).contains(values[5])
    else { throw TreeError.invalidProperties }
    let shadow = try reader.integer(UInt32.self)
    let border = try reader.integer(UInt32.self)
    let colors = try (0..<count).map { _ in try reader.integer(UInt32.self) }
    let mask = Int(try reader.integer(UInt16.self))
    guard reader.remaining == 0, mask <= 511 else { throw TreeError.invalidProperties }
    return Self(
      mode: mode, presentationBackground: flags & 1 != 0, colors: colors, radius: values[0],
      shadowRadius: values[1],
      shadowX: values[2], shadowY: values[3], borderWidth: values[4], opacity: values[5],
      shadowColor: shadow, borderColor: border, recipe: recipe, overrideMask: mask,
      capsule: flags & 4 != 0, shapeExplicit: flags & 8 != 0, contentInset: flags & 2 != 0)
  }
}

@MainActor enum NativeSurface {
  static var definition: NativeViewDefinition {
    BonsaiNativeViews.definition(
      version: 3, capabilities: [], decode: RenderSurface.decode,
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
  @Environment(\.bonsaiDefaults) private var defaults
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  private var p: RenderSurface {
    context.properties.resolved(defaults, scheme: scheme, contrast: contrast)
  }
  private var child: some View {
    let action = context.properties.recipe == 2
    let inset = p.contentInset ? defaults.metric(3) : 0
    return context.children[0]
      .padding(.horizontal, p.contentInset ? inset : action ? defaults.metric(5) : 0)
      .padding(.vertical, p.contentInset ? inset : action ? defaults.metric(6) : 0)
      .environment(\.bonsaiRowSpacing, action ? defaults.metric(4) : nil)
  }
  private var shape: SurfaceShape {
    SurfaceShape(radius: p.radius, capsule: p.capsule)
  }

  private var background: some View {
    NativeSurfacePaint(properties: p, reduceTransparency: reduceTransparency)
  }

  private var content: some View {
    child
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
        child
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
  @Environment(\.bonsaiDefaults) private var defaults
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  private var p: RenderSurface { properties.resolved(defaults, scheme: scheme, contrast: contrast) }
  private var shape: SurfaceShape {
    SurfaceShape(radius: p.radius, capsule: p.capsule)
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

private struct SurfaceShape: InsettableShape {
  var radius: Double
  var capsule: Bool
  var inset: CGFloat = 0
  func path(in rect: CGRect) -> Path {
    RoundedRectangle(
      cornerRadius: max(0, (capsule ? rect.height / 2 : radius) - inset), style: .continuous
    )
    .path(in: rect.insetBy(dx: inset, dy: inset))
  }
  func inset(by amount: CGFloat) -> Self {
    var result = self
    result.inset += amount
    return result
  }
}
