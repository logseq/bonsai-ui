import SwiftUI

@MainActor protocol NativePanTarget: AnyObject {
  func canBegin(_ translation: CGSize) -> Bool
  func begin()
  func change(_ translation: CGSize)
  func end(cancelled: Bool)
}

#if os(macOS)
  import AppKit
  final class RemovalPanRecognizer: NSPanGestureRecognizer {
    private var origin: CGPoint?
    private(set) var displacement: CGSize = .zero

    override func mouseDown(with event: NSEvent) {
      origin = event.locationInWindow
      displacement = .zero
      super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
      measure(event)
      super.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) {
      measure(event)
      super.mouseUp(with: event)
    }
    override func reset() {
      super.reset()
      origin = nil
      displacement = .zero
    }
    override func canBePrevented(by other: NSGestureRecognizer) -> Bool {
      // A descendant Button begins tracking on mouse-down. Keep observing until
      // directional admission either starts the pan or rejects it for scrolling.
      false
    }
    private func measure(_ event: NSEvent) {
      guard let origin, let view else { return }
      let start = view.convert(origin, from: nil)
      let end = view.convert(event.locationInWindow, from: nil)
      displacement = CGSize(
        width: end.x - start.x,
        height: (end.y - start.y) * (view.isFlipped ? 1 : -1))
    }
  }
  struct NativeRemovalPan: NSGestureRecognizerRepresentable {
    let controller: any NativePanTarget
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
      Coordinator(controller)
    }
    func makeNSGestureRecognizer(context: Context) -> RemovalPanRecognizer {
      let gesture = RemovalPanRecognizer()
      gesture.delegate = context.coordinator
      gesture.delaysPrimaryMouseButtonEvents = true
      return gesture
    }
    func handleNSGestureRecognizerAction(_ gesture: RemovalPanRecognizer, context: Context) {
      let translation = gesture.displacement
      switch gesture.state {
      case .began:
        controller.begin()
        controller.change(translation)
      case .changed: controller.change(translation)
      case .ended:
        controller.change(translation)
        controller.end(cancelled: false)
      case .cancelled, .failed: controller.end(cancelled: true)
      default: break
      }
    }
    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
      let controller: any NativePanTarget
      init(_ controller: any NativePanTarget) { self.controller = controller }
      func gestureRecognizerShouldBegin(_ recognizer: NSGestureRecognizer) -> Bool {
        guard let pan = recognizer as? RemovalPanRecognizer else { return false }
        // NSPan's translation is still zero during this callback; use the complete mouse travel.
        return controller.canBegin(pan.displacement)
      }
      func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
      ) -> Bool {
        guard let view = gestureRecognizer.view else { return false }
        var child = view.hitTest(view.convert(event.locationInWindow, from: nil))
        while let candidate = child, candidate !== view {
          if candidate is NSTextView || candidate is NSSlider { return false }
          child = candidate.superview
        }
        return true
      }
    }
  }
#else
  import UIKit
  struct NativeRemovalPan: UIGestureRecognizerRepresentable {
    let controller: any NativePanTarget
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
      Coordinator(controller)
    }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
      let gesture = UIPanGestureRecognizer()
      gesture.maximumNumberOfTouches = 1
      gesture.delegate = context.coordinator
      return gesture
    }
    func handleUIGestureRecognizerAction(_ gesture: UIPanGestureRecognizer, context: Context) {
      let point = gesture.translation(in: gesture.view)
      let translation = CGSize(width: point.x, height: point.y)
      switch gesture.state {
      case .began:
        controller.begin()
        controller.change(translation)
      case .changed: controller.change(translation)
      case .ended:
        controller.change(translation)
        controller.end(cancelled: false)
      case .cancelled, .failed: controller.end(cancelled: true)
      default: break
      }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      let controller: any NativePanTarget
      init(_ controller: any NativePanTarget) { self.controller = controller }
      func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
        let value = pan.translation(in: pan.view)
        return controller.canBegin(CGSize(width: value.x, height: value.y))
      }
      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
        -> Bool
      {
        var child = touch.view
        while let candidate = child, candidate !== gestureRecognizer.view {
          if candidate is UITextView || candidate is UITextField || candidate is UISlider {
            return false
          }
          child = candidate.superview
        }
        return true
      }
    }
  }
#endif
