import Foundation

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

enum NativeHapticKind: UInt8, Equatable, Sendable {
  case light, medium, heavy, selection
}

extension NativeWindowHost {
  /// Completion means submission to the native API; hardware and user settings own delivery.
  func performFeedback(_ kind: NativeHapticKind) throws {
    let window = try boundWindow()
    guard allowsFeedback?() == true else { throw CancellationError() }
    #if os(macOS)
      guard window.isVisible, !window.isMiniaturized else { throw CancellationError() }
      // AppKit has no impact-weight or selection pattern. Generic is its native equivalent.
      NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    #else
      guard !window.isHidden, window.alpha > 0,
        let view = window.rootViewController?.view, view.window === window
      else { throw CancellationError() }
      feedbackGenerators.perform(kind, in: view)
    #endif
  }
}

#if os(iOS)
  /// UIKit attaches these generators as interactions; keep at most four per owned view.
  @MainActor final class NativeFeedbackGenerators {
    private weak var view: UIView?
    private var impacts: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private var selection: UISelectionFeedbackGenerator?

    func perform(_ kind: NativeHapticKind, in view: UIView) {
      if self.view !== view {
        reset()
        self.view = view
      }
      switch kind {
      case .light: impact(.light, in: view)
      case .medium: impact(.medium, in: view)
      case .heavy: impact(.heavy, in: view)
      case .selection:
        let generator = selection ?? UISelectionFeedbackGenerator(view: view)
        selection = generator
        generator.prepare()
        generator.selectionChanged()
      }
    }
    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, in view: UIView) {
      let generator = impacts[style] ?? UIImpactFeedbackGenerator(style: style, view: view)
      impacts[style] = generator
      generator.prepare()
      generator.impactOccurred()
    }
    func reset() {
      for generator in impacts.values { generator.view?.removeInteraction(generator) }
      if let selection { selection.view?.removeInteraction(selection) }
      impacts.removeAll()
      selection = nil
      view = nil
    }
  }
#endif
