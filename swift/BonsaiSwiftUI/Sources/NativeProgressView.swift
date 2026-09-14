import SwiftUI

struct RenderProgress: Equatable, Sendable {
  let value: Double?
  let circular: Bool

  static func decode(_ reader: inout WireReader) throws -> Self {
    let value = try reader.flag() ? reader.finiteDouble() : nil
    if let value, !(0...1).contains(value) { throw TreeError.invalidProperties }
    return Self(value: value, circular: try reader.flag())
  }
}

struct NativeProgressView: View {
  let properties: RenderProgress
  let animationsActive: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var visible = false

  var body: some View {
    ProgressView(value: properties.value, total: 1)
      .progressViewStyle(
        NativeProgressStyle(
          circular: properties.circular,
          animate: visible && animationsActive && scenePhase == .active && !reduceMotion)
      )
      .accessibilityValue(
        Text(
          properties.value ?? 0,
          format: .percent.precision(.fractionLength(0))), isEnabled: properties.value != nil
      )
      .onAppear { visible = true }
      .onDisappear { visible = false }
  }
}

// A single native style preserves determinate circular and indeterminate
// linear behavior on both supported platforms. Interpolation never enters FFI.
private struct NativeProgressStyle: ProgressViewStyle {
  let circular: Bool
  let animate: Bool
  @Environment(\.controlSize) private var controlSize
  @Environment(\.layoutDirection) private var direction

  private var diameter: CGFloat {
    switch controlSize {
    case .mini: 16
    case .small: 20
    case .regular: 24
    case .large: 32
    case .extraLarge: 40
    @unknown default: 24
    }
  }

  func makeBody(configuration: Configuration) -> some View {
    let value = configuration.fractionCompleted
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: value != nil || !animate)) {
      context in
      let phase =
        animate && value == nil
        ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
        : 0.5
      if circular {
        ZStack {
          Circle().stroke(.tint.opacity(0.18), lineWidth: 3)
          Circle().trim(from: 0, to: value ?? 0.25)
            .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90 + (value == nil ? phase * 360 : 0)))
            .opacity(value == 0 ? 0 : 1)
        }
        .padding(1.5)
        .frame(width: diameter, height: diameter)
      } else {
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            Capsule().fill(.tint.opacity(0.18))
            Capsule().fill(.tint)
              .frame(width: geometry.size.width * (value ?? 0.3))
              .offset(
                x: value == nil
                  ? (phase * 1.6 - 0.3) * geometry.size.width * (direction == .leftToRight ? 1 : -1)
                  : 0)
          }
          .clipShape(Capsule())
        }
        .frame(height: max(3, diameter / 6))
        .frame(idealWidth: 160, maxWidth: .infinity)
      }
    }
  }
}
