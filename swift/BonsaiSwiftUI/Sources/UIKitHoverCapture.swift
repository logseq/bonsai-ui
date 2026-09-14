#if os(iOS)
  import UIKit

  final class UIKitHoverCapture: UIView {
    var onGeometry: (() -> Void)?
    private var captureEnabled = false
    private var disposed = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override var isHidden: Bool { didSet { onGeometry?() } }
    override func didMoveToWindow() {
      super.didMoveToWindow()
      onGeometry?()
    }
    override func layoutSubviews() {
      super.layoutSubviews()
      onGeometry?()
    }
    func setCaptureEnabled(_ enabled: Bool) {
      guard !disposed, enabled != captureEnabled else { return }
      captureEnabled = enabled
      onGeometry?()
    }

    private var eligible: Bool {
      guard captureEnabled, !disposed, window != nil else {
        return false
      }
      var ancestor: UIView? = self
      while let view = ancestor {
        if view.isHidden || view.alpha <= 0 { return false }
        ancestor = view.superview
      }
      return true
    }

    func locate(_ sample: HoverRouter.Sample) -> HoverRouter.Hit? {
      guard eligible, let window, ObjectIdentifier(window) == sample.window else {
        return nil
      }
      let position = CGPoint(
        x: sample.pointer.position.x + window.bounds.minX,
        y: sample.pointer.position.y + window.bounds.minY)
      let local = convert(position, from: window)
      let pointer = NativePointer(
        id: sample.pointer.id, localX: local.x - bounds.minX, localY: local.y - bounds.minY,
        globalX: sample.pointer.position.x, globalY: sample.pointer.position.y,
        kind: sample.pointer.kind, buttons: sample.pointer.buttons)
      var inside = bounds.contains(local) && window.bounds.contains(position)
      var ancestor = superview
      while inside, let view = ancestor {
        if view.clipsToBounds && !view.bounds.contains(view.convert(position, from: window)) {
          inside = false
        }
        ancestor = view.superview
      }
      return HoverRouter.Hit(pointer: pointer, inside: inside)
    }

    func dispose() {
      guard !disposed else { return }
      disposed = true
      captureEnabled = false
      onGeometry?()
      onGeometry = nil
    }
  }
#endif
