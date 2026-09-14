import Observation
import SwiftUI

struct RenderAnimatedOpacity: Equatable, Sendable {
  let opacity: Double
  let animationID: UInt64
  let milliseconds: UInt32
  let curve: Int

  static func decode(_ reader: inout WireReader) throws -> Self {
    let opacity = try reader.finiteDouble()
    let id = try reader.integer(UInt64.self)
    guard (0...1).contains(opacity), id <= UInt64(Int64.max) else {
      throw TreeError.invalidProperties
    }
    return Self(
      opacity: opacity, animationID: id,
      milliseconds: try reader.integer(UInt32.self), curve: try reader.choice(3))
  }
  var animation: Animation {
    let seconds = Double(milliseconds) / 1000
    switch curve {
    case 0: return .linear(duration: seconds)
    case 1: return .easeIn(duration: seconds)
    case 2: return .easeOut(duration: seconds)
    default: return .easeInOut(duration: seconds)
    }
  }
}

@MainActor @Observable final class AnimatedOpacityController {
  private(set) var value: AnimatablePair<Double, Double>
  @ObservationIgnored private var properties: RenderAnimatedOpacity
  @ObservationIgnored private let emit: (NativeEventPayload) -> Bool
  @ObservationIgnored private var generation: UInt64 = 0
  @ObservationIgnored private var pending = false
  @ObservationIgnored private var running = false
  @ObservationIgnored private var ready = false
  @ObservationIgnored private var active = false
  @ObservationIgnored private var mounted = 0
  @ObservationIgnored private var reducedMotion = false
  @ObservationIgnored private var disposed = false

  init(_ properties: RenderAnimatedOpacity, emit: @escaping (NativeEventPayload) -> Bool) {
    self.properties = properties
    self.emit = emit
    value = AnimatablePair(properties.opacity, 0)
  }
  func replace(_ next: RenderAnimatedOpacity) {
    guard !disposed, next != properties else { return }
    properties = next
    generation &+= 1
    pending = true
    running = false
    ready = false
    active = false
    if mounted == 0 { start(animation: nil) }
  }
  func attach() {
    mounted += 1
    advance()
  }
  func detach() {
    mounted = max(0, mounted - 1)
    if mounted == 0, pending { start(animation: nil) }
  }
  func setReducedMotion(_ value: Bool) {
    reducedMotion = value
    if value && running { start(animation: nil) }
    advance()
  }
  func setPresentationActive(_ value: Bool) {
    active = value
    if !value && running { start(animation: nil) }
    advance()
  }
  func canComplete(_ id: UInt64) -> Bool {
    !disposed && active && mounted > 0 && pending && ready && properties.animationID == id
  }
  func dispose() {
    disposed = true
    generation &+= 1
    pending = false
    running = false
    ready = false
  }

  private func advance() {
    guard !disposed, active, mounted > 0, pending else { return }
    if ready {
      if emit(.animationCompleted(properties.animationID)) {
        pending = false
        ready = false
      }
      return
    }
    guard !running else { return }
    let animation =
      reducedMotion || properties.milliseconds == 0 || value.first == properties.opacity
      ? nil : properties.animation
    start(animation: animation)
  }
  private func start(animation: Animation?) {
    running = true
    ready = false
    generation &+= 1
    let token = generation
    // A nil animation preserves existing interpolation; zero duration replaces it.
    withAnimation(animation ?? .linear(duration: 0), completionCriteria: .removed) {
      value.first = properties.opacity
      // An unchanged alpha does not invalidate an existing SwiftUI animation.
      // Change a second animatable coordinate to cancel without remounting content.
      if animation == nil { value.second = 1 - value.second }
    } completion: { [weak self] in
      Task { @MainActor in self?.completed(token) }
    }
  }
  private func completed(_ token: UInt64) {
    guard !disposed, pending, generation == token else { return }
    running = false
    ready = true
    advance()
  }
}

struct NativeAnimatedOpacity: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let node: RenderNodeState
  let controller: AnimatedOpacityController
  let activate: @MainActor (RenderNodeState) -> Void
  var body: some View {
    NativeNodeView(node: node.children[0], activate: activate)
      .modifier(NativeOpacityEffect(value: controller.value))
      .onAppear {
        controller.setReducedMotion(reduceMotion)
        controller.attach()
      }
      .onDisappear { controller.detach() }
      .onChange(of: reduceMotion) { _, value in controller.setReducedMotion(value) }
  }
}

struct NativeOpacityEffect: AnimatableModifier {
  nonisolated var value: AnimatablePair<Double, Double>
  nonisolated var animatableData: AnimatablePair<Double, Double> {
    get { value }
    set { value = newValue }
  }
  func body(content: Content) -> some View {
    content.opacity(value.first)
  }
}
