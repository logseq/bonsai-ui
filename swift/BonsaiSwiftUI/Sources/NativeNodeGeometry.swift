import Observation
import SwiftUI

struct NodeLayoutObservation: Hashable {
  let identity: RenderIdentity
  let attachment: UUID
  let sample: UUID
}

/// Only this target's publisher observes its requested sample.
@MainActor @Observable final class NodeLayoutTarget {
  let identity: RenderIdentity
  private(set) var observation: NodeLayoutObservation?
  @ObservationIgnored private(set) var attachment: UUID?
  @ObservationIgnored private(set) weak var registry: NativeLayoutRequests?
  @ObservationIgnored private var disposed = false

  init(identity: RenderIdentity) { self.identity = identity }

  func attach(_ owner: UUID, registry: NativeLayoutRequests?) {
    guard !disposed else { return }
    if attachment != owner || self.registry !== registry { detach() }
    attachment = owner
    self.registry = registry
  }

  func detach(owner: UUID? = nil) {
    guard owner == nil || attachment == owner else { return }
    registry?.invalidate(self)
    attachment = nil
    registry = nil
  }

  func requestObservation() -> NodeLayoutObservation? {
    guard let attachment, !disposed else { return nil }
    let next = NodeLayoutObservation(identity: identity, attachment: attachment, sample: UUID())
    observation = next
    return next
  }

  func clearObservation() { observation = nil }
  func contentChanged() { registry?.resample(self) }
  func dispose() {
    detach()
    disposed = true
  }
}

/// Window-owned requests. An unresolved native layout times out after two seconds.
/// Waiting never blocks a presentation transaction or the main actor.
@MainActor final class NativeLayoutRequests {
  private struct Waiter {
    let continuation: CheckedContinuation<CGRect, any Error>
    let valid: () -> Bool
    let timeout: Task<Void, Never>
  }
  private struct Pending {
    let target: NodeLayoutTarget
    var observation: NodeLayoutObservation
    var waiters: [UUID: Waiter]
  }
  private var pending: [RenderIdentity: Pending] = [:]
  private let timeout: Duration
  var subscriptionCount: Int { pending.count }

  init(timeout: Duration = .seconds(2)) { self.timeout = timeout }

  func measure(_ target: NodeLayoutTarget, valid: @escaping () -> Bool) async throws -> CGRect {
    try Task.checkCancellation()
    guard target.registry === self, target.attachment != nil, valid() else {
      throw HostServiceError.failed("The target has no attached presented layout")
    }
    let request = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }
        if pending[target.identity] == nil {
          guard let observation = target.requestObservation() else {
            continuation.resume(throwing: HostServiceError.failed("The layout target is detached"))
            return
          }
          pending[target.identity] = Pending(target: target, observation: observation, waiters: [:])
        }
        let timer = Task { @MainActor [weak self, timeout] in
          do { try await Task.sleep(for: timeout) } catch { return }
          self?.finish(
            target.identity, request: request,
            result: .failure(HostServiceError.failed("Native layout measurement timed out")))
        }
        pending[target.identity]?.waiters[request] = Waiter(
          continuation: continuation, valid: valid, timeout: timer)
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.finish(target.identity, request: request, result: .failure(CancellationError()))
      }
    }
  }

  private func finish(_ identity: RenderIdentity, request: UUID, result: Result<CGRect, any Error>)
  {
    guard let waiter = pending[identity]?.waiters.removeValue(forKey: request) else { return }
    if pending[identity]?.waiters.isEmpty == true {
      pending.removeValue(forKey: identity)?.target.clearObservation()
    }
    waiter.timeout.cancel()
    waiter.continuation.resume(with: result)
  }

  func observe(_ frames: [NodeLayoutObservation: CGRect]) {
    for (observation, frame) in frames {
      guard let item = pending[observation.identity], item.observation == observation,
        item.target.registry === self, item.target.attachment == observation.attachment,
        frame.width >= 0, frame.height >= 0,
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
      else { continue }
      for (request, waiter) in item.waiters {
        finish(
          observation.identity, request: request,
          result: waiter.valid()
            ? .success(frame)
            : .failure(HostServiceError.failed("The layout target is no longer presented")))
      }
    }
  }

  func resample(_ target: NodeLayoutTarget) {
    guard pending[target.identity]?.target === target,
      let observation = target.requestObservation()
    else { return }
    pending[target.identity]?.observation = observation
  }

  func invalidate(_ target: NodeLayoutTarget) {
    guard let item = pending[target.identity], item.target === target else { return }
    for request in item.waiters.keys {
      finish(
        target.identity, request: request,
        result: .failure(HostServiceError.failed("The layout target was removed or detached")))
    }
  }

  func reset() {
    for item in Array(pending.values) { invalidate(item.target) }
  }
}

private struct NativeLayoutRequestsKey: EnvironmentKey {
  static let defaultValue: NativeLayoutRequests? = nil
}

extension EnvironmentValues {
  var nativeLayoutRequests: NativeLayoutRequests? {
    get { self[NativeLayoutRequestsKey.self] }
    set { self[NativeLayoutRequestsKey.self] = newValue }
  }
}

enum NodeLayoutAnchors: PreferenceKey {
  static let defaultValue: [NodeLayoutObservation: Anchor<CGRect>] = [:]
  static func reduce(
    value: inout [NodeLayoutObservation: Anchor<CGRect>],
    nextValue: () -> [NodeLayoutObservation: Anchor<CGRect>]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

struct NativeLayoutPublisher: ViewModifier {
  let target: NodeLayoutTarget
  @Environment(\.nativeLayoutRequests) private var registry
  @State private var owner = UUID()

  func body(content: Content) -> some View {
    content
      .background {
        if let observation = target.observation {
          Color.clear.anchorPreference(key: NodeLayoutAnchors.self, value: .bounds) {
            [observation: $0]
          }
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
      }
      .onAppear { target.attach(owner, registry: registry) }
      .onChange(of: registry.map(ObjectIdentifier.init)) { _, _ in
        target.attach(owner, registry: registry)
      }
      .onDisappear { target.detach(owner: owner) }
  }

}

/// Resolve only outstanding requests in the application-root coordinate space.
struct NativeLayoutObserver: ViewModifier {
  let requests: NativeLayoutRequests

  func body(content: Content) -> some View {
    content
      .environment(\.nativeLayoutRequests, requests)
      .overlayPreferenceValue(NodeLayoutAnchors.self) { anchors in
        if !anchors.isEmpty {
          GeometryReader { geometry in
            let frames = anchors.mapValues { geometry[$0] }
            Color.clear.onChange(of: frames, initial: true) { _, frames in
              requests.observe(frames)
            }
          }
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
      }
      .onDisappear { requests.reset() }
  }
}
