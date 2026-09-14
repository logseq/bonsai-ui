#if os(iOS)
  import UIKit

  @MainActor final class NativeKeyboardHost {
    private var controllers: [KeyboardListenerController] = []
    private var windows: [ObjectIdentifier: UIKitKeyboardSource] = [:]

    func replace(_ controllers: [KeyboardListenerController], parents: [UInt64: UInt64]) {
      for controller in self.controllers { controller.onWindowChange = nil }
      self.controllers = controllers
      for controller in controllers {
        var path = [controller.id]
        var parent = parents[controller.id.node]
        while let id = parent {
          path.append(RenderIdentity(epoch: controller.id.epoch, node: id))
          parent = parents[id]
        }
        controller.setPath(path)
        controller.onWindowChange = { [weak self] in self?.synchronizeWindows() }
      }
      synchronizeWindows()
    }

    private func synchronizeWindows() {
      var mounted: [ObjectIdentifier: UIWindow] = [:]
      for controller in controllers {
        if let window = controller.capture.window { mounted[ObjectIdentifier(window)] = window }
      }
      for id in Array(windows.keys) where mounted[id] == nil {
        windows.removeValue(forKey: id)?.dispose()
      }
      for (id, window) in mounted where windows[id] == nil {
        windows[id] = UIKitKeyboardSource(window: window) { [weak self, weak window] in
          guard let self, let window else { return [] }
          let candidates = self.controllers.filter {
            $0.isCollecting && $0.capture.window === window
          }.sorted { $0.path.count > $1.path.count }
          guard let deepest = candidates.first else { return [] }
          let path = Set(deepest.path)
          return candidates.filter { path.contains($0.id) }
        }
      }
    }

    isolated deinit {
      for source in windows.values { source.dispose() }
    }
  }

  @MainActor private final class UIKitKeyboardSource {
    private weak var window: UIWindow?
    private let targets: () -> [KeyboardListenerController]
    private var mapper = UIKitKeyMapper()
    private var route = NativeKeyboardRoute()
    private var presses = NativeKeyboardPresses()
    private var recognizers: [KeyboardPressRecognizer] = []
    private var notifications: [NSObjectProtocol] = []

    init(window: UIWindow, targets: @escaping () -> [KeyboardListenerController]) {
      self.window = window
      self.targets = targets
      for intercepts in [false, true] {
        let recognizer = KeyboardPressRecognizer(intercepts: intercepts)
        recognizer.receive = { [weak self] press, phase in
          self?.receive(press, phase: phase) == true
        }
        window.addGestureRecognizer(recognizer)
        recognizers.append(recognizer)
      }
      for name in [
        UITextField.textDidBeginEditingNotification, UITextField.textDidEndEditingNotification,
        UITextView.textDidBeginEditingNotification, UITextView.textDidEndEditingNotification,
        UIFocusSystem.didUpdateNotification, UIWindow.didResignKeyNotification,
        UIApplication.didEnterBackgroundNotification,
      ] {
        notifications.append(
          NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main
          ) { [weak self] _ in
            MainActor.assumeIsolated { self?.retire() }
          })
      }
    }

    private func retire() {
      route.reset()
      mapper.reset()
      presses.retire()
    }

    private func receive(_ press: UIPress, phase: NativeKeyboardPresses.Phase) -> Bool {
      guard let window, press.window === window, !window.isHidden, window.isKeyWindow,
        let nativeKey = press.key, let source = UInt64(exactly: nativeKey.keyCode.rawValue)
      else { return false }
      let targets = targets()
      let signature = targets.map {
        NativeKeyboardRoute.Target(
          id: $0.id, generation: $0.generation, focusGeneration: $0.focus.inputGeneration,
          handled: $0.properties.handled)
      }
      if route.prepare(signature, responder: press.responder.map(ObjectIdentifier.init)) {
        mapper.reset()
        presses.retire()
      }
      let timestamp = press.timestamp
      let targetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
      let deliver: (RenderIdentity, NativeKey) -> Bool = { [targetsByID] id, key in
        targetsByID[id]?.receive(key) == true
      }
      let handled = presses.receive(
        source: source, sequence: press, timestamp: timestamp, phase: phase
      ) { action in
        guard let action else {
          route.cancel(source)
          _ = mapper.translate(nativeKey, action: .up)
          return false
        }
        if action == .down { _ = mapper.translate(nativeKey, action: .up) }
        let key = mapper.translate(nativeKey, action: action)
        return route.dispatch(key, source: source, receive: deliver)
      }
      if phase != .began {
        // Both recognizers see the same native callback before this task runs.
        // A later press cannot be removed by cleanup from an earlier release.
        Task { @MainActor [weak self] in
          self?.presses.finish(source: source, timestamp: timestamp)
        }
      }
      return handled
    }

    func dispose() {
      window = nil
      for observer in notifications { NotificationCenter.default.removeObserver(observer) }
      notifications.removeAll()
      for recognizer in recognizers {
        recognizer.receive = nil
        recognizer.view?.removeGestureRecognizer(recognizer)
      }
      recognizers.removeAll()
      route.reset()
      mapper.reset()
      presses = NativeKeyboardPresses()
    }
  }

  @MainActor private final class KeyboardPressRecognizer: UIGestureRecognizer {
    var receive: ((UIPress, NativeKeyboardPresses.Phase) -> Bool)?
    private let intercepts: Bool
    private var active = Set<ObjectIdentifier>()

    init(intercepts: Bool) {
      self.intercepts = intercepts
      super.init(target: nil, action: nil)
      cancelsTouchesInView = intercepts
      delaysTouchesBegan = false
      delaysTouchesEnded = false
      allowedTouchTypes = []
    }
    required init?(coder: NSCoder) { fatalError("Programmatic recognizer only") }

    override func shouldReceive(_ event: UIEvent) -> Bool {
      guard let event = event as? UIPressesEvent else { return false }
      // Learn the native press types from keyboard-bearing events. UIKit does
      // not expose a keyboard case in UIPress.PressType; no private raw value
      // or TV-remote default is assumed here.
      let types = Set(event.allPresses.filter { $0.key != nil }.map { $0.type.rawValue })
      allowedPressTypes = types.map { NSNumber(value: $0) }
      return !types.isEmpty
    }
    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
      for press in presses {
        guard press.key != nil else {
          ignore(press, for: event)
          continue
        }
        let handled = receive?(press, .began) == true
        if intercepts && !handled {
          active.remove(ObjectIdentifier(press))
          ignore(press, for: event)
        } else {
          active.insert(ObjectIdentifier(press))
        }
      }
      if active.isEmpty {
        state = state == .possible ? .failed : .cancelled
      } else {
        state = state == .possible ? .began : .changed
      }
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent) {
      // Force/analog changes do not imply keyboard auto-repeat.
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
      finish(presses, phase: .ended)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
      finish(presses, phase: .cancelled)
    }
    private func finish(_ presses: Set<UIPress>, phase: NativeKeyboardPresses.Phase) {
      for press in presses where active.remove(ObjectIdentifier(press)) != nil {
        _ = receive?(press, phase)
      }
      if active.isEmpty { state = phase == .cancelled ? .cancelled : .ended }
    }
    override func reset() {
      super.reset()
      active.removeAll()
    }
  }
#endif
