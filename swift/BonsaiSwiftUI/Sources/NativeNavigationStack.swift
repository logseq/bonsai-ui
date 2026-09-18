import Observation
import SwiftUI

struct RenderNavigationDestination: Equatable, Sendable {
  let key: String
  let title: String
  let canPop: Bool

  static func == (left: Self, right: Self) -> Bool {
    left.key.utf8.elementsEqual(right.key.utf8) && left.title == right.title
      && left.canPop == right.canPop
  }

  static func decode(_ reader: inout WireReader) throws -> Self {
    let key = try reader.string()
    guard !key.isEmpty else { throw TreeError.invalidProperties }
    return Self(key: key, title: try reader.string(), canPop: try reader.flag())
  }
}

struct NavigationRouteIdentity: Hashable {
  let node: RenderIdentity
  let key: Data
  var link: NavigationLinkRequest? = nil
  var core: CoreNavigationLinkRequest? = nil
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.node == rhs.node && lhs.key == rhs.key }
  func hash(into hasher: inout Hasher) {
    hasher.combine(node)
    hasher.combine(key)
  }
}

@MainActor final class NavigationLinkRequest {
  let controller: ObjectIdentifier
  let path: [NavigationRouteIdentity]
  let emission: NativeViewEmission
  let admit: () -> Bool
  init(
    controller: NavigationStackController, emission: NativeViewEmission, admit: @escaping () -> Bool
  ) {
    self.controller = ObjectIdentifier(controller)
    self.path = controller.path
    self.emission = emission
    self.admit = admit
  }
}

@MainActor final class CoreNavigationLinkRequest {
  let controller: ObjectIdentifier
  let path: [NavigationRouteIdentity]
  let valid: () -> Bool
  let ready: () -> Bool
  let activated: () -> Void
  let emit: (UUID) -> Bool
  init(
    controller: NavigationStackController, valid: @escaping () -> Bool,
    ready: @escaping () -> Bool, activated: @escaping () -> Void, emit: @escaping (UUID) -> Bool
  ) {
    self.controller = ObjectIdentifier(controller)
    self.path = controller.path
    self.valid = valid
    self.ready = ready
    self.activated = activated
    self.emit = emit
  }
}

@MainActor @Observable final class NavigationStackController {
  @ObservationIgnored var onPresentationChange: (() -> Void)?
  private(set) var path: [NavigationRouteIdentity] = [] {
    didSet { if oldValue != path { onPresentationChange?() } }
  }
  private var destinations: [RenderNodeState] = []
  private var committedPath: [NavigationRouteIdentity] = []

  private func identity(_ node: RenderNodeState) -> NavigationRouteIdentity {
    guard case .navigationDestination(let destination) = node.properties else {
      preconditionFailure("Invalid navigation destination")
    }
    return NavigationRouteIdentity(node: node.id, key: Data(destination.key.utf8))
  }
  private var pending = false
  private var disposed = false
  private var pendingLink: NativeViewEmission?
  private var pathRevision: UInt64 = 0
  private struct CoreIntent {
    let serial = UUID()
    let request: CoreNavigationLinkRequest
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
    var emitted = false
  }
  private var coreIntent: CoreIntent?
  @ObservationIgnored private var coreExpiry: Task<Void, Never>?

  func coreLinkValue(
    valid: @escaping () -> Bool, ready: @escaping () -> Bool,
    activated: @escaping () -> Void = {}, emit: @escaping (UUID) -> Bool
  ) -> NavigationRouteIdentity {
    NavigationRouteIdentity(
      node: RenderIdentity(epoch: 0, node: 0),
      key: Data(UUID().uuidString.utf8),
      core: CoreNavigationLinkRequest(
        controller: self, valid: valid, ready: ready, activated: activated, emit: emit))
  }

  func cancelUndeliveredCoreLink() {
    guard coreIntent?.emitted != true else { return }
    coreIntent = nil
    coreExpiry?.cancel()
    coreExpiry = nil
  }

  @discardableResult func retryCoreLink() -> Bool {
    guard let intent = coreIntent else { return false }
    if intent.emitted { return true }
    guard !disposed, intent.request.path == path, intent.request.valid(),
      ContinuousClock.now < intent.deadline
    else {
      cancelUndeliveredCoreLink()
      return false
    }
    guard intent.request.ready() else { return true }
    // Transport rejection is terminal for this explicit click.
    guard intent.request.emit(intent.serial) else {
      cancelUndeliveredCoreLink()
      return false
    }
    coreIntent?.emitted = true
    coreExpiry?.cancel()
    coreExpiry = nil
    return true
  }

  func resolveCoreLink(_ serial: UUID) {
    guard coreIntent?.serial == serial, coreIntent?.emitted == true else { return }
    coreIntent = nil
    pathRevision &+= 1
  }

  func linkValue(emission: NativeViewEmission, admit: @escaping () -> Bool)
    -> NavigationRouteIdentity
  {
    NavigationRouteIdentity(
      node: RenderIdentity(epoch: 0, node: 0), key: Data(UUID().uuidString.utf8),
      link: NavigationLinkRequest(controller: self, emission: emission, admit: admit))
  }

  func resolveLink(_ emission: NativeViewEmission) {
    if pendingLink == emission {
      pendingLink = nil
      pathRevision &+= 1
    }
  }

  func synchronize(_ children: [RenderNodeState]) {
    let next = Array(children.dropFirst())
    let nextPath = next.map(identity)
    if nextPath != committedPath {
      pending = false
      cancelUndeliveredCoreLink()
    }
    committedPath = nextPath
    destinations = next
    if !pending { path = nextPath }
  }

  func resolve() {
    pending = false
    path = committedPath
  }

  @discardableResult func request(
    _ requested: [NavigationRouteIdentity], emit: (NativeEventPayload) -> Bool
  ) -> Bool {
    guard !disposed, !pending, pendingLink == nil, coreIntent?.emitted != true else { return false }
    if requested.count == path.count + 1, Array(requested.dropLast()) == path,
      let core = requested.last?.core,
      core.controller == ObjectIdentifier(self), core.path == path, core.valid()
    {
      cancelUndeliveredCoreLink()
      let intent = CoreIntent(request: core)
      coreIntent = intent
      coreExpiry = Task { @MainActor [weak self] in
        do { try await Task.sleep(until: intent.deadline, clock: .continuous) } catch { return }
        guard self?.coreIntent?.serial == intent.serial else { return }
        self?.cancelUndeliveredCoreLink()
      }
      return retryCoreLink()
    }
    if requested.count == path.count + 1, Array(requested.dropLast()) == path,
      let link = requested.last?.link,
      link.controller == ObjectIdentifier(self), link.path == path
    {
      cancelUndeliveredCoreLink()
      guard link.admit() else { return false }
      pendingLink = link.emission
      return true
    }
    guard requested.count < path.count,
      Array(path.prefix(requested.count)) == requested,
      destinations.dropFirst(requested.count).allSatisfy({
        if case .navigationDestination(let destination) = $0.properties {
          return destination.canPop
        }
        return false
      })
    else { return false }
    let keys = destinations.prefix(requested.count).map {
      guard case .navigationDestination(let destination) = $0.properties else {
        preconditionFailure("Invalid navigation child")
      }
      return destination.key
    }
    guard emit(.navigationPath(keys)) else { return false }
    cancelUndeliveredCoreLink()
    pending = true
    path = requested
    return true
  }

  func binding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<[NavigationRouteIdentity]> {
    _ = pathRevision
    let expectedPath = path
    return Binding(
      get: { self.path },
      set: {
        // SwiftUI optimistically changes its internal path even when admission fails.
        // Re-publish the controlled path without inventing a destination.
        defer { self.pathRevision &+= 1 }
        if let core = $0.last?.core, core.controller == ObjectIdentifier(self) { core.activated() }
        guard self.path == expectedPath else { return }
        self.request($0, emit: emit)
      })
  }

  func destination(_ id: NavigationRouteIdentity) -> RenderNodeState? {
    destinations.first { identity($0) == id }
  }

  func dispose() {
    disposed = true
    coreIntent = nil
    coreExpiry?.cancel()
    coreExpiry = nil
    pending = false
    pendingLink = nil
    path = []
    destinations = []
    committedPath = []
  }
}

struct NativeNavigationStack: View {
  let node: RenderNodeState
  let title: String
  let controller: NavigationStackController
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    NavigationStack(path: controller.binding(emit: node.emit)) {
      NativeNodeView(node: node.children[0], activate: activate)
        .navigationTitle(title)
        .navigationDestination(for: NavigationRouteIdentity.self) { identity in
          if let destination = controller.destination(identity) {
            NativeNodeView(node: destination, activate: activate)
          }
        }
    }
    .environment(\.bonsaiNavigationStack, controller)
  }
}

private struct BonsaiNavigationStackKey: EnvironmentKey {
  static let defaultValue: NavigationStackController? = nil
}
extension EnvironmentValues {
  var bonsaiNavigationStack: NavigationStackController? {
    get { self[BonsaiNavigationStackKey.self] }
    set { self[BonsaiNavigationStackKey.self] = newValue }
  }
}

struct NativeNavigationLink<Label: View>: View {
  @Environment(\.bonsaiNavigationStack) private var controller
  let emission: NativeViewEmission?
  let admit: () -> Bool
  let canInteract: () -> Bool
  let label: Label

  var body: some View {
    let value = emission.flatMap { controller?.linkValue(emission: $0, admit: admit) }
    NavigationLink(value: value) { label }
      .disabled(value == nil || !canInteract())
  }
}

struct NativeCoreNavigationLink: View {
  @Environment(\.bonsaiListRowInteraction) private var listRowInteraction
  @Environment(\.bonsaiNavigationStack) private var controller
  let node: RenderNodeState
  let activation: String
  let enabled: Bool
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    let handler = node.bindings[EventTagId.press]
    let expected = node.properties
    let value = controller.flatMap { owner in
      handler.map { handler in
        owner.coreLinkValue(
          valid: { [weak node] in
            guard let node else { return false }
            return node.coreLinkMounted && node.coreLinkEligible
              && node.properties == expected && node.bindings[EventTagId.press] == handler
          }, ready: { [weak node] in node?.coreLinkReady == true },
          activated: { listRowInteraction?.labelActivated() },
          emit: { [weak node] serial in
            node?.emit(
              .navigationActivation(serial: serial, handler: handler, activation: activation))
              ?? false
          })
      }
    }
    let requestActivation = {
      guard enabled, let controller, let value, let request = value.core else { return }
      request.activated()
      _ = controller.request(request.path + [value], emit: node.emit)
    }
    NavigationLink(value: value) {
      NativeNodeView(node: node.children[0], activate: activate)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .disabled(!enabled || controller == nil)
    // Default value-link activation creates transient SwiftUI route state even
    // when the path binding rejects it. Admit the intent before native routing;
    // only the subsequent OCaml path may push a destination.
    .highPriorityGesture(TapGesture().onEnded { requestActivation() })
    .accessibilityAction { requestActivation() }
    .onKeyPress(keys: [.return, .space], phases: .down) { _ in
      requestActivation()
      return .handled
    }
    .onAppear {
      node.coreLinkMounted = true
      controller?.retryCoreLink()
    }
    .onDisappear {
      node.coreLinkMounted = false
      controller?.retryCoreLink()
    }
  }
}
