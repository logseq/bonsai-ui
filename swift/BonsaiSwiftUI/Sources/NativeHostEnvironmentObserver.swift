import SwiftUI

/// Observe the application boundary without introducing a second hosting graph.
struct NativeHostEnvironmentObserver: View {
  let session: BonsaiSession
  @State private var sourceID = UUID()
  @Environment(\.displayScale) private var displayScale
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.locale) private var locale
  @Environment(\.legibilityWeight) private var legibilityWeight
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @Environment(\.accessibilityInvertColors) private var invertColors
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.layoutDirection) private var direction
  @ScaledMetric(relativeTo: .body) private var bodyScale: Double = 1

  private func sample(size: CGSize, safeArea: NativeHostEnvironment.Insets) -> NativeHostEnvironment
  {
    #if os(macOS)
      let platform = NativeHostEnvironment.Platform.macos
      let pointers: UInt32 = 0x0e
    #else
      let platform = NativeHostEnvironment.Platform.ios
      let pointers: UInt32 = 0x0f
    #endif
    return NativeHostEnvironment(
      viewportWidth: size.width, viewportHeight: size.height,
      devicePixelRatio: displayScale, textScale: bodyScale,
      brightness: colorScheme == .dark ? .dark : .light, platform: platform,
      locale: locale.identifier(.bcp47), safeArea: safeArea,
      keyboardInsets: .init(), accessibleNavigation: voiceOver,
      boldText: legibilityWeight == .bold, invertColors: invertColors,
      disableAnimations: reduceMotion, reducedMotion: reduceMotion,
      highContrast: contrast == .increased,
      orientation: size.width > size.height ? .landscape : .portrait,
      // Host capability mask, not an inventory of connected input devices.
      pointerKinds: pointers)
  }

  var body: some View {
    Group {
      #if os(macOS)
        GeometryReader { geometry in
          let insets = geometry.safeAreaInsets
          let value = sample(
            size: geometry.size,
            safeArea: .init(
              left: direction == .leftToRight ? insets.leading : insets.trailing,
              top: insets.top,
              right: direction == .leftToRight ? insets.trailing : insets.leading,
              bottom: insets.bottom))
          Color.clear
            .onAppear { session.beginEnvironmentObservation(source: sourceID, sample: value) }
            .onChange(of: value) { _, value in session.observeEnvironment(value, source: sourceID) }
            .onDisappear { session.endEnvironmentObservation(source: sourceID) }
        }
      #else
        NativeUIKitEnvironmentProbe(
          session: session, source: sourceID, preferences: sample(size: .zero, safeArea: .init()))
      #endif
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
