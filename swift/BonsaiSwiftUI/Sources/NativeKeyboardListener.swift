import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct RenderKeyboardListener: Equatable, Sendable {
  let autofocus: Bool
  let handled: Bool
  static func decode(_ reader: inout WireReader) throws -> Self {
    try Self(autofocus: reader.flag(), handled: reader.choice(1) == 0)
  }
}

@MainActor final class KeyboardListenerController {
  let id: RenderIdentity
  let focus: FocusScopeController
  let capture = KeyboardCaptureView(frame: .zero)
  private(set) var properties: RenderKeyboardListener
  private(set) var generation: UInt64 = 0
  private(set) var handler: UInt64?
  private(set) var path: [RenderIdentity] = []
  private let emit: (NativeEventPayload) -> Bool
  private var disposed = false
  var onWindowChange: (() -> Void)?

  init(
    id: RenderIdentity, properties: RenderKeyboardListener, handler: UInt64?,
    emit: @escaping (NativeEventPayload) -> Bool
  ) {
    self.id = id
    self.properties = properties
    self.handler = handler
    self.emit = emit
    focus = FocusScopeController(
      autofocus: properties.autofocus, handler: nil, emit: { _ in false })
    capture.onWindow = { [weak self] in
      self?.generation += 1
      self?.onWindowChange?()
    }
  }

  var isCollecting: Bool {
    !disposed && handler != nil && focus.hasFocus && capture.window != nil
      && capture.isCaptureVisible
  }

  func synchronize(_ properties: RenderKeyboardListener, handler: UInt64?) {
    guard !disposed, self.properties != properties || self.handler != handler else { return }
    generation += 1
    self.properties = properties
    self.handler = handler
    focus.setPresented(false)
    focus.synchronize(autofocus: properties.autofocus, handler: nil)
  }

  func setPath(_ path: [RenderIdentity]) {
    guard self.path != path else { return }
    generation += 1
    self.path = path
  }

  func receive(_ key: NativeKey) -> Bool {
    isCollecting && emit(.key(key))
  }

  func dispose() {
    disposed = true
    generation += 1
    focus.dispose()
    capture.onWindow = nil
    onWindowChange = nil
  }
}

#if os(macOS)
  @MainActor final class KeyboardCaptureView: NSView {
    var isCaptureVisible: Bool { !isHiddenOrHasHiddenAncestor }
    var onWindow: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { onWindow?() }
  }

  private struct KeyboardMount: NSViewRepresentable {
    let controller: KeyboardListenerController
    func makeNSView(context: Context) -> KeyboardCaptureView { controller.capture }
    func updateNSView(_ view: KeyboardCaptureView, context: Context) {}
  }

#else
  @MainActor final class KeyboardCaptureView: UIView {
    var onWindow: (() -> Void)?
    var isCaptureVisible: Bool {
      var ancestor: UIView? = self
      while let view = ancestor {
        if view.isHidden || view.alpha <= 0 { return false }
        ancestor = view.superview
      }
      return true
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func didMoveToWindow() {
      super.didMoveToWindow()
      onWindow?()
    }
  }
  private struct KeyboardMount: UIViewRepresentable {
    let controller: KeyboardListenerController
    func makeUIView(context: Context) -> KeyboardCaptureView { controller.capture }
    func updateUIView(_ view: KeyboardCaptureView, context: Context) {}
  }
#endif

struct NativeKeyboardListener<Content: View>: View {
  let controller: KeyboardListenerController
  let content: Content
  var body: some View {
    NativeFocusScope(controller: controller.focus, content: content)
      .background(KeyboardMount(controller: controller))
  }
}

#if os(macOS)
  @MainActor final class NativeKeyboardHost {
    @MainActor private final class WindowState {
      weak var window: NSWindow?
      var mapper = AppKitKeyMapper()
      var route = NativeKeyboardRoute()
      private var observation: NSKeyValueObservation?
      init(_ window: NSWindow) {
        self.window = window
        observation = window.observe(\.firstResponder) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.reset() }
        }
      }
      func reset() {
        mapper.reset()
        route.reset()
      }
    }
    private var controllers: [KeyboardListenerController] = []
    private var windows: [ObjectIdentifier: WindowState] = [:]
    private var monitor: Any?

    func replace(_ controllers: [KeyboardListenerController], parents: [UInt64: UInt64]) {
      self.controllers = controllers
      for controller in controllers {
        var path = [controller.id]
        var parent = parents[controller.id.node]
        while let id = parent {
          path.append(RenderIdentity(epoch: controller.id.epoch, node: id))
          parent = parents[id]
        }
        controller.setPath(path)
      }
      if controllers.isEmpty {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        windows.removeAll()
      } else if monitor == nil {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) {
          [weak self] event in
          let handled = MainActor.assumeIsolated {
            guard let self else { return false }
            return self.receive(event) == nil
          }
          return handled ? nil : event
        }
      }
    }

    isolated deinit {
      if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func receive(_ event: NSEvent) -> NSEvent? {
      guard let window = event.window, window.isVisible else { return event }
      let windowID = ObjectIdentifier(window)
      windows = windows.filter { $0.value.window != nil }
      guard let firstResponder = window.firstResponder, firstResponder !== window else {
        windows.removeValue(forKey: windowID)
        return event
      }
      let candidates = controllers.filter { $0.isCollecting && $0.capture.window === window }
        .sorted { $0.path.count > $1.path.count }
      guard let deepest = candidates.first else {
        windows.removeValue(forKey: windowID)
        return event
      }
      let path = Set(deepest.path)
      let targets = candidates.filter { path.contains($0.id) }
      let route = targets.map {
        NativeKeyboardRoute.Target(
          id: $0.id, generation: $0.generation,
          focusGeneration: $0.focus.inputGeneration, handled: $0.properties.handled)
      }
      let state = windows[windowID] ?? WindowState(window)
      windows[windowID] = state
      // AppKit reuses a field editor across text fields. Its delegate identifies
      // the actual focus owner when the first-responder object stays the same.
      let owner: AnyObject
      if let editor = firstResponder as? NSTextView, editor.isFieldEditor,
        let delegate = editor.delegate
      {
        owner = delegate
      } else {
        owner = firstResponder
      }
      let responder = ObjectIdentifier(owner)
      if state.route.prepare(route, responder: responder) { state.mapper.reset() }
      guard let key = state.mapper.translate(event) else { return event }
      let targetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
      let handled = state.route.dispatch(key, source: UInt64(event.keyCode)) { id, key in
        targetsByID[id]?.receive(key) == true
      }
      return handled ? nil : event
    }
  }
#endif
