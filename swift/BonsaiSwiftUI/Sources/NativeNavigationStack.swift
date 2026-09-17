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
    if nextPath != committedPath { pending = false }
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
    guard !disposed, !pending, pendingLink == nil else { return false }
    if requested.count == path.count + 1, Array(requested.dropLast()) == path,
      let link = requested.last?.link,
      link.controller == ObjectIdentifier(self), link.path == path
    {
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
        guard self.path == expectedPath else { return }
        self.request($0, emit: emit)
      })
  }

  func destination(_ id: NavigationRouteIdentity) -> RenderNodeState? {
    destinations.first { identity($0) == id }
  }

  func dispose() {
    disposed = true
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
