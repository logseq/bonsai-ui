import Observation
import SwiftUI

struct RenderRefresh: Equatable, Sendable {
  let token: Int64
  let state: Int
  let show: Int64?
  static func decode(_ reader: inout WireReader) throws -> Self {
    let token = try Int64(bitPattern: reader.integer(UInt64.self))
    let state = try reader.choice(2)
    let show = try reader.flag() ? Int64(bitPattern: reader.integer(UInt64.self)) : nil
    return Self(token: token, state: state, show: show)
  }
}

@MainActor @Observable final class RefreshController {
  private(set) var properties: RenderRefresh
  private(set) var pending: Int64?
  private(set) var presented = false
  private(set) var generation: UInt64 = 0
  private var consumed: Int64?
  private var lastShow: Int64?
  private var disposed = false
  private var pulling = false
  private var armed = false
  @ObservationIgnored private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
  @ObservationIgnored private var programmatic: Task<Void, Never>?
  @ObservationIgnored private let emit: (NativeEventPayload) -> Bool

  init(_ properties: RenderRefresh, emit: @escaping (NativeEventPayload) -> Bool) {
    self.properties = properties
    self.emit = emit
  }
  var busy: Bool { pending != nil || properties.state == 1 }
  var canRequest: Bool {
    presented && !disposed && !busy && properties.state == 0 && consumed != properties.token
  }
  private func finish() {
    pending = nil
    let current = waiters.values
    waiters.removeAll()
    for waiter in current { waiter.resume() }
  }
  func synchronize(_ next: RenderRefresh) {
    guard next != properties else { return }
    if next.token != properties.token {
      finish()
      consumed = nil
      generation += 1
      armed = false
      pulling = false
    } else if next.state == 2 {
      finish()
    }
    properties = next
  }
  func invalidateBinding() {
    finish()
    generation += 1
    armed = false
    pulling = false
    presented = false
  }
  func setPresentation(presented: Bool, active: Bool) {
    self.presented = presented && active && !disposed
    if !active {
      invalidateBinding()
      programmatic?.cancel()
      programmatic = nil
    }
    if self.presented, let show = properties.show, show != lastShow, canRequest {
      lastShow = show
      let expected = generation
      programmatic = Task { [weak self] in await self?.perform(generation: expected) }
    }
  }
  func perform(generation expected: UInt64? = nil) async {
    guard !Task.isCancelled, expected == nil || expected == generation else { return }
    if pending == nil {
      guard canRequest else { return }
      let token = properties.token
      pending = token
      guard emit(.refreshRequest(token)) else {
        finish()
        return
      }
      consumed = token
    }
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled || pending == nil {
          continuation.resume()
        } else {
          waiters[id] = continuation
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.waiters.removeValue(forKey: id)?.resume()
        if self.waiters.isEmpty { self.pending = nil }
      }
    }
  }
  func pull(offset: Double, interacting: Bool, generation expected: UInt64) -> Bool {
    guard expected == generation, canRequest, offset.isFinite else {
      pulling = false
      armed = false
      return false
    }
    if interacting {
      pulling = true
      armed = offset <= -72
      return false
    }
    let trigger = pulling && armed
    pulling = false
    armed = false
    return trigger
  }
  func dispose() {
    disposed = true
    invalidateBinding()
    programmatic?.cancel()
    programmatic = nil
  }
}

private struct RefreshOwnerKey: EnvironmentKey {
  static let defaultValue: RefreshController? = nil
}
extension EnvironmentValues {
  var bonsaiRefresh: RefreshController? {
    get { self[RefreshOwnerKey.self] }
    set { self[RefreshOwnerKey.self] = newValue }
  }
}

private struct RefreshButton: View {
  let controller: RefreshController
  @Environment(\.refresh) private var refresh
  var body: some View {
    HStack {
      Button("Refresh", systemImage: "arrow.clockwise") {
        Task { await refresh?() }
      }.disabled(!controller.canRequest)
      if controller.busy { ProgressView().controlSize(.small).accessibilityLabel("Refreshing") }
      Spacer(minLength: 0)
    }.padding(8)
  }
}

struct NativeRefresh: View {
  let node: RenderNodeState
  let controller: RefreshController
  let activate: @MainActor (RenderNodeState) -> Void
  var body: some View {
    let generation = controller.generation
    return VStack(spacing: 0) {
      RefreshButton(controller: controller)
      NativeNodeView(node: node.children[0], activate: activate)
        .environment(\.bonsaiRefresh, controller)
    }
    .refreshable { await controller.perform(generation: generation) }
    .onDisappear { controller.setPresentation(presented: false, active: false) }
  }
}

// Applied directly to each ScrollView. Its content clears the environment so a
// nested scroll cannot issue a refresh on its ancestor's behalf.
struct RefreshScrollModifier: ViewModifier {
  @Environment(\.bonsaiRefresh) private var controller
  @Environment(\.refresh) private var refresh
  @State private var interacting = false
  func body(content: Content) -> some View {
    let generation = controller?.generation ?? 0
    content
      .onScrollGeometryChange(for: Double.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top
      } action: { _, offset in
        if interacting {
          _ = controller?.pull(offset: offset, interacting: true, generation: generation)
        }
      }
      .onScrollPhaseChange { _, phase, context in
        interacting = phase == .interacting
        let offset = context.geometry.contentOffset.y + context.geometry.contentInsets.top
        if controller?.pull(offset: offset, interacting: interacting, generation: generation)
          == true
        {
          Task { await refresh?() }
        }
      }
  }
}
