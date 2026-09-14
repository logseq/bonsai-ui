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
}

@MainActor @Observable final class NavigationStackController {
  private(set) var path: [NavigationRouteIdentity] = []
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
    guard !disposed, !pending, requested.count < path.count,
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
    let expectedPath = path
    return Binding(
      get: { self.path },
      set: {
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
  }
}
