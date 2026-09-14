#if os(iOS)
  import UIKit

  @MainActor final class UIKitHoverSource: NSObject, HoverWindowSource, UIGestureRecognizerDelegate
  {
    private weak var window: UIWindow?
    private let receive: @MainActor (HoverInput.Change) -> Void
    private var mouseHover: UIHoverGestureRecognizer?
    private var pencilHover: UIHoverGestureRecognizer?
    private var contactObserver: HoverMouseContactRecognizer?
    private var input = HoverInput()

    init(window: UIWindow, receive: @escaping @MainActor (HoverInput.Change) -> Void) {
      self.window = window
      self.receive = receive
      super.init()
      let mouse = UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:)))
      mouse.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
      let pencil = UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:)))
      pencil.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
      let contact = HoverMouseContactRecognizer()
      contact.onSample = { [weak self] position, buttons, phase in
        guard let self, let window = self.window, self.contactObserver?.view === window else {
          return
        }
        let sample = HoverSample(id: 0, kind: .mouse, position: position, buttons: buttons)
        if let change = self.input.mouseContact(sample, phase: phase) { self.forward(change) }
      }
      mouseHover = mouse
      pencilHover = pencil
      contactObserver = contact
      for recognizer in [mouse, pencil, contact] {
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
      }
    }

    @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
      guard let window, recognizer.view === window,
        recognizer === mouseHover || recognizer === pencilHover,
        let buttons = UInt32(exactly: recognizer.buttonMask.rawValue)
      else { return }
      let isMouse = recognizer === mouseHover
      let sample = HoverSample(
        id: isMouse ? 0 : 1, kind: isMouse ? .mouse : .stylus,
        position: recognizer.location(in: window), buttons: buttons)
      let present: Bool
      switch recognizer.state {
      case .began, .changed: present = true
      case .ended, .cancelled, .failed: present = false
      default: return
      }
      if let change = input.hover(sample, present: present) { forward(change) }
    }

    private func forward(_ change: HoverInput.Change) {
      guard let window, !window.isHidden else { return }
      let sample = change.sample
      receive(
        HoverInput.Change(
          sample: HoverSample(
            id: sample.id, kind: sample.kind,
            position: CGPoint(
              x: sample.position.x - window.bounds.minX,
              y: sample.position.y - window.bounds.minY), buttons: sample.buttons),
          present: change.present))
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }

    func dispose() {
      window = nil
      contactObserver?.onSample = nil
      for recognizer in [mouseHover, pencilHover, contactObserver].compactMap({ $0 }) {
        recognizer.removeTarget(self, action: nil)
        recognizer.delegate = nil
        recognizer.view?.removeGestureRecognizer(recognizer)
      }
      mouseHover = nil
      pencilHover = nil
      contactObserver = nil
      input.reset()
    }
  }

  private final class HoverMouseContactRecognizer: UIGestureRecognizer {
    var onSample: ((CGPoint, UInt32, HoverInput.ContactPhase) -> Void)?
    private var active = false
    private var lastSample: (CGPoint, UInt32)?

    override init(target: Any?, action: Selector?) {
      super.init(target: target, action: action)
      allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
      cancelsTouchesInView = false
      delaysTouchesBegan = false
      delaysTouchesEnded = false
    }
    required init?(coder: NSCoder) { fatalError("Programmatic recognizer only") }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
      false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesBegan(touches, with: event)
      let continued = active
      active = true
      state = continued ? .changed : .began
      sample(touches, event: event, phase: .active)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesMoved(touches, with: event)
      guard active else { return }
      state = .changed
      sample(touches, event: event, phase: .active)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesEnded(touches, with: event)
      guard active else { return }
      active = !event.buttonMask.isEmpty
      state = active ? .changed : .ended
      sample(touches, event: event, phase: .ended)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesCancelled(touches, with: event)
      guard active else { return }
      active = false
      state = .cancelled
      sample(touches, event: event, phase: .cancelled)
    }
    override func reset() {
      super.reset()
      let previous = lastSample
      lastSample = nil
      let cancelled = active
      active = false
      if cancelled, let previous { onSample?(previous.0, previous.1, .cancelled) }
    }

    private func sample(_ touches: Set<UITouch>, event: UIEvent, phase: HoverInput.ContactPhase) {
      guard let window = view as? UIWindow,
        let touch = touches.filter({ $0.type == .indirectPointer && $0.window === window })
          .max(by: { $0.timestamp < $1.timestamp }),
        let buttons = UInt32(exactly: event.buttonMask.rawValue)
      else { return }
      let point = touch.location(in: window)
      lastSample = (point, buttons)
      onSample?(point, buttons, phase)
    }
  }
#endif
