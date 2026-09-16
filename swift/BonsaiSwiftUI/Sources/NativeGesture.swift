import SwiftUI

#if os(macOS)
  import AppKit
  private typealias PlatformGestureRecognizer = NSGestureRecognizer
#else
  import UIKit
  private typealias PlatformGestureRecognizer = UIGestureRecognizer
#endif

enum NativeGestureCoordinateSpace: Hashable { case application }

extension NativeEventPayload {
  var isGenericGesture: Bool {
    switch self {
    case .tap, .doubleTap, .longPress, .pointerDown, .pointerUp: true
    default: false
    }
  }
}

private enum GestureRole {
  case tap, doubleTap, longPress, pointer
  func isEnabled(_ bindings: [Int: UInt64]) -> Bool {
    switch self {
    case .tap: bindings[EventTagId.tap] != nil
    case .doubleTap: bindings[EventTagId.doubleTap] != nil
    case .longPress: bindings[EventTagId.longPress] != nil
    case .pointer: bindings[EventTagId.pointerDown] != nil || bindings[EventTagId.pointerUp] != nil
    }
  }
}

@MainActor final class NativeGestureController {
  private struct Registration {
    weak var recognizer: PlatformGestureRecognizer?
    let role: GestureRole
  }
  #if os(macOS)
    let pointerDevices = AppKitPointerDevices.acquire()
  #endif
  private var registrations: [Registration] = []
  private var bindings: [Int: UInt64]
  private let emit: (NativeEventPayload) -> Bool
  private var presented = false
  private var mounted = false
  private var disposed = false
  private(set) var generation: UInt64 = 1
  var isActionable: Bool {
    bindings[EventTagId.tap] != nil || bindings[EventTagId.doubleTap] != nil
      || bindings[EventTagId.longPress] != nil
  }
  var isCollecting: Bool { presented && mounted && !disposed }

  init(bindings: [Int: UInt64], emit: @escaping (NativeEventPayload) -> Bool) {
    self.bindings = bindings
    self.emit = emit
  }
  func synchronize(_ bindings: [Int: UInt64]) {
    guard !disposed, self.bindings != bindings else { return }
    self.bindings = bindings
    invalidate()
  }
  func setPresented(_ presented: Bool) {
    guard !disposed, self.presented != presented else { return }
    self.presented = presented
    invalidate()
  }
  func setMounted(_ mounted: Bool) {
    guard !disposed, self.mounted != mounted else { return }
    self.mounted = mounted
    invalidate()
  }
  func dispose() {
    guard !disposed else { return }
    disposed = true
    #if os(macOS)
      pointerDevices.release()
    #endif
    invalidate()
    registrations.removeAll()
  }
  private func invalidate() {
    generation += 1
    registrations.removeAll { $0.recognizer == nil }
    for registration in registrations { registration.recognizer?.isEnabled = false }
    for registration in registrations {
      registration.recognizer?.isEnabled = isCollecting && registration.role.isEnabled(bindings)
    }
  }
  fileprivate func register(_ recognizer: PlatformGestureRecognizer, role: GestureRole) {
    registrations.removeAll { $0.recognizer == nil }
    registrations.append(Registration(recognizer: recognizer, role: role))
    recognizer.isEnabled = isCollecting && role.isEnabled(bindings)
    #if os(iOS)
      for first in registrations {
        for second in registrations {
          if requiresFailure(first.role, of: second.role), let a = first.recognizer,
            let b = second.recognizer
          {
            a.require(toFail: b)
          }
        }
      }
    #endif
  }
  fileprivate func role(of recognizer: PlatformGestureRecognizer) -> GestureRole? {
    registrations.first { $0.recognizer === recognizer }?.role
  }
  fileprivate func requiresFailure(_ first: GestureRole, of second: GestureRole) -> Bool {
    first == .tap && (second == .doubleTap || second == .longPress)
      || first == .doubleTap && second == .longPress
  }
  fileprivate func send(_ payload: NativeEventPayload, generation: UInt64) {
    guard isCollecting, self.generation == generation, bindings[payload.tag] != nil else { return }
    _ = emit(payload)
  }
}

struct NativeGestureContent<Content: View>: View {
  let controller: NativeGestureController
  let content: Content
  var body: some View {
    content.modifier(NativeInteractiveBounds(enabled: controller.isActionable)).contentShape(
      Rectangle()
    )
    .gesture(NativeGesture(controller: controller, role: .tap))
    .gesture(NativeGesture(controller: controller, role: .doubleTap))
    .gesture(NativeGesture(controller: controller, role: .longPress))
    .gesture(NativeGesture(controller: controller, role: .pointer))
    .onAppear { controller.setMounted(true) }
    .onDisappear { controller.setMounted(false) }
  }
}

#if os(macOS)
  @MainActor private final class GestureCoordinator: NSObject, NSGestureRecognizerDelegate {
    let controller: NativeGestureController
    let role: GestureRole
    var generation: UInt64 = 0
    var device = AppKitPointerDevice(id: 0, kind: .mouse)
    init(controller: NativeGestureController, role: GestureRole) {
      self.controller = controller
      self.role = role
    }
    func gestureRecognizer(
      _ gestureRecognizer: NSGestureRecognizer,
      shouldAttemptToRecognizeWith event: NSEvent
    ) -> Bool {
      guard controller.isCollecting,
        [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
        let device = controller.pointerDevices.device(for: event)
      else { return false }
      generation = controller.generation
      self.device = device
      return true
    }
    func gestureRecognizer(
      _ gestureRecognizer: NSGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
      guard let other = controller.role(of: otherGestureRecognizer) else { return false }
      return controller.requiresFailure(role, of: other)
    }
    func gestureRecognizer(
      _ gestureRecognizer: NSGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
      role == .pointer || controller.role(of: otherGestureRecognizer) == .pointer
    }
  }

  @MainActor private final class PassivePointerRecognizer: NSGestureRecognizer {
    var point = CGPoint.zero
    var buttons: UInt32 = 0
    var isDown = false
    override init(target: Any?, action: Selector?) {
      super.init(target: target, action: action)
      delaysPrimaryMouseButtonEvents = false
      delaysSecondaryMouseButtonEvents = false
      delaysOtherMouseButtonEvents = false
    }
    required init?(coder: NSCoder) { fatalError("Programmatic recognizer") }
    override func canPrevent(_ preventedGestureRecognizer: NSGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: NSGestureRecognizer) -> Bool {
      false
    }
    override func location(in view: NSView?) -> NSPoint {
      view?.convert(point, from: nil) ?? point
    }
    private func receive(_ event: NSEvent, down: Bool) {
      point = event.locationInWindow
      isDown = down
      let mask = UInt32(1) << UInt32(clamping: min(event.buttonNumber, 31))
      if down { buttons |= mask } else { buttons &= ~mask }
      state = down ? (state == .possible ? .began : .changed) : (buttons == 0 ? .ended : .changed)
    }
    override func mouseDown(with event: NSEvent) {
      super.mouseDown(with: event)
      receive(event, down: true)
    }
    override func mouseUp(with event: NSEvent) {
      super.mouseUp(with: event)
      receive(event, down: false)
    }
    override func rightMouseDown(with event: NSEvent) {
      super.rightMouseDown(with: event)
      receive(event, down: true)
    }
    override func rightMouseUp(with event: NSEvent) {
      super.rightMouseUp(with: event)
      receive(event, down: false)
    }
    override func otherMouseDown(with event: NSEvent) {
      super.otherMouseDown(with: event)
      receive(event, down: true)
    }
    override func otherMouseUp(with event: NSEvent) {
      super.otherMouseUp(with: event)
      receive(event, down: false)
    }
    override func mouseCancelled(with event: NSEvent) {
      super.mouseCancelled(with: event)
      state = .cancelled
    }
    override func reset() {
      super.reset()
      buttons = 0
    }
  }

  private struct NativeGesture: NSGestureRecognizerRepresentable {
    let controller: NativeGestureController
    let role: GestureRole
    func makeCoordinator(converter: CoordinateSpaceConverter) -> GestureCoordinator {
      GestureCoordinator(controller: controller, role: role)
    }
    func makeNSGestureRecognizer(context: Context) -> NSGestureRecognizer {
      let recognizer: NSGestureRecognizer
      switch role {
      case .tap, .doubleTap:
        let click = NSClickGestureRecognizer()
        click.numberOfClicksRequired = role == .tap ? 1 : 2
        recognizer = click
      case .longPress: recognizer = NSPressGestureRecognizer()
      case .pointer: recognizer = PassivePointerRecognizer(target: nil, action: nil)
      }
      recognizer.delegate = context.coordinator
      controller.register(recognizer, role: role)
      return recognizer
    }
    func handleNSGestureRecognizerAction(_ recognizer: NSGestureRecognizer, context: Context) {
      let local = context.converter.localLocation
      let global = context.converter.location(in: .named(NativeGestureCoordinateSpace.application))
      let tap = NativeTap(
        localX: local.x, localY: local.y, globalX: global.x, globalY: global.y,
        kind: context.coordinator.device.kind)
      let payload: NativeEventPayload
      switch role {
      case .tap where recognizer.state == .ended: payload = .tap(tap)
      case .doubleTap where recognizer.state == .ended: payload = .doubleTap(tap)
      case .longPress where recognizer.state == .began: payload = .longPress
      case .pointer where [.began, .changed, .ended].contains(recognizer.state):
        guard let pointer = recognizer as? PassivePointerRecognizer else { return }
        let value = NativePointer(
          id: context.coordinator.device.id, localX: local.x, localY: local.y,
          globalX: global.x, globalY: global.y, kind: context.coordinator.device.kind,
          buttons: pointer.buttons)
        payload = pointer.isDown ? .pointerDown(value) : .pointerUp(value)
      default: return
      }
      controller.send(payload, generation: context.coordinator.generation)
    }
  }
#else
  private func pointerKind(_ touch: UITouch) -> NativePointer.Kind {
    switch touch.type {
    case .direct: .touch
    case .pencil: .stylus
    case .indirect, .indirectPointer: .mouse
    @unknown default: .unknown
    }
  }

  @MainActor private final class GestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    let controller: NativeGestureController
    let role: GestureRole
    var generation: UInt64 = 0
    var kind = NativePointer.Kind.touch
    init(controller: NativeGestureController, role: GestureRole) {
      self.controller = controller
      self.role = role
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
      -> Bool
    {
      guard controller.isCollecting else { return false }
      if role == .pointer { gestureRecognizer.view?.isMultipleTouchEnabled = true }
      generation = controller.generation
      kind = pointerKind(touch)
      return true
    }
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      role == .pointer || controller.role(of: otherGestureRecognizer) == .pointer
    }
  }
  @MainActor private final class PassivePointerRecognizer: UIGestureRecognizer {
    let input = PointerContactInput()
    let controller: NativeGestureController
    init(controller: NativeGestureController) {
      self.controller = controller
      super.init(target: nil, action: nil)
      requiresExclusiveTouchType = false
    }
    required init?(coder: NSCoder) { fatalError("Programmatic recognizer") }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
      false
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesBegan(touches, with: event)
      guard controller.isCollecting else { return }
      for touch in touches {
        let kind = pointerKind(touch)
        input.begin(
          touch, kind: kind, position: touch.location(in: nil),
          buttons: kind == .mouse ? UInt32(clamping: event.buttonMask.rawValue) : 1,
          generation: controller.generation)
      }
      if input.hasActiveContacts { state = state == .possible ? .began : .changed }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesEnded(touches, with: event)
      guard input.hasActiveContacts else { return }
      for touch in touches {
        input.end(
          touch, position: touch.location(in: nil),
          buttons: pointerKind(touch) == .mouse ? UInt32(clamping: event.buttonMask.rawValue) : 0)
      }
      state = input.hasActiveContacts ? .changed : .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesCancelled(touches, with: event)
      guard input.hasActiveContacts else { return }
      for touch in touches { input.cancel(touch) }
      state = input.hasActiveContacts ? .changed : .cancelled
    }
    override func reset() {
      super.reset()
      input.reset()
    }
  }
  private struct NativeGesture: UIGestureRecognizerRepresentable {
    let controller: NativeGestureController
    let role: GestureRole
    func makeCoordinator(converter: CoordinateSpaceConverter) -> GestureCoordinator {
      GestureCoordinator(controller: controller, role: role)
    }
    func makeUIGestureRecognizer(context: Context) -> UIGestureRecognizer {
      let recognizer: UIGestureRecognizer
      switch role {
      case .tap, .doubleTap:
        let tap = UITapGestureRecognizer()
        tap.numberOfTapsRequired = role == .tap ? 1 : 2
        recognizer = tap
      case .longPress: recognizer = UILongPressGestureRecognizer()
      case .pointer: recognizer = PassivePointerRecognizer(controller: controller)
      }
      recognizer.cancelsTouchesInView = false
      recognizer.delaysTouchesBegan = false
      recognizer.delaysTouchesEnded = false
      recognizer.delegate = context.coordinator
      controller.register(recognizer, role: role)
      return recognizer
    }
    func updateUIGestureRecognizer(_ recognizer: UIGestureRecognizer, context: Context) {
      if role == .pointer { recognizer.view?.isMultipleTouchEnabled = true }
    }
    func handleUIGestureRecognizerAction(_ recognizer: UIGestureRecognizer, context: Context) {
      if let pointer = recognizer as? PassivePointerRecognizer {
        for sample in pointer.input.drain() {
          let local = context.converter.convert(globalPoint: sample.position)
          let global = context.converter.convert(
            globalPoint: sample.position,
            to: .named(NativeGestureCoordinateSpace.application))
          controller.send(
            sample.payload(local: local, global: global), generation: sample.generation)
        }
        return
      }
      let local = context.converter.localLocation
      let global = context.converter.location(in: .named(NativeGestureCoordinateSpace.application))
      let tap = NativeTap(
        localX: local.x, localY: local.y, globalX: global.x, globalY: global.y,
        kind: context.coordinator.kind)
      let payload: NativeEventPayload
      switch role {
      case .tap where recognizer.state == .ended: payload = .tap(tap)
      case .doubleTap where recognizer.state == .ended: payload = .doubleTap(tap)
      case .longPress where recognizer.state == .began: payload = .longPress
      default: return
      }
      controller.send(payload, generation: context.coordinator.generation)
    }
  }
#endif
