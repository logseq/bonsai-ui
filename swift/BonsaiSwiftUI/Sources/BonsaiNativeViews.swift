import Observation
import SwiftUI

/// Capabilities required by an OCaml application extension.
public struct BonsaiNativeCapabilities: OptionSet, Sendable {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
  public static let stateful = Self(rawValue: 1)
  public static let resource = Self(rawValue: 2)
  public static let semantics = Self(rawValue: 4)
  public static let semanticsCanvas = Self(rawValue: 8)
  public static let virtualized = Self(rawValue: 16)
  var isValid: Bool { rawValue & ~31 == 0 }
}

public enum BonsaiNativeViewError: Error, Equatable {
  case invalidRegistration
  case duplicateKind(UInt32)
  case unregisteredKind(UInt32)
  case incompatibleVersion(UInt32, UInt16)
  case unsupportedCapabilities(UInt32)
}

/// An application-defined event. IDs must be nonzero; payloads use the frame byte budget.
public struct BonsaiNativeEvent: Sendable {
  public let id: UInt16
  public let payload: Data
  public init(id: UInt16, payload: Data = Data()) {
    self.id = id
    self.payload = payload
  }
}

/// A typed view snapshot. Retained emit callbacks expire when this snapshot loses ownership.
@MainActor public struct BonsaiNativeContext<Properties, Event, Resource> {
  public let properties: Properties
  public let resource: Resource
  public let children: [BonsaiNativeChild]
  public let isPresented: Bool
  /// Query current ownership before a local action that does not emit an OCaml event.
  public let canInteract: () -> Bool
  public let emit: (Event) -> Bool
}

/// A keyed OCaml child. Omitted or unmounted children cannot continue dispatching input.
@MainActor public struct BonsaiNativeChild: View, Identifiable {
  public let id: UInt64
  let node: RenderNodeState
  let owner: NativeViewInstance
  let activate: @MainActor (RenderNodeState) -> Void
  public var body: some View {
    NativeNodeView(node: node, activate: activate)
      .onAppear { owner.mountChild(node.id) }
      .onDisappear { owner.unmountChild(node.id) }
  }
}

/// Build a registry before starting an application. Each session receives a value snapshot.
@MainActor public struct BonsaiNativeViews {
  private var definitions: [UInt32: NativeViewDefinition] = [:]
  public nonisolated init() {}

  public mutating func register<Properties, Event, Resource, Content: View>(
    kind: UInt32, version: UInt16, capabilities: BonsaiNativeCapabilities = [],
    decode: @escaping (Data) throws -> Properties,
    validateChildren: @escaping (Properties, Int) throws -> Void = { _, _ in },
    encodeEvent: @escaping (Event) -> BonsaiNativeEvent,
    makeResource: @escaping () -> Resource, dispose: @escaping (Resource) -> Void,
    @ViewBuilder content: @escaping (BonsaiNativeContext<Properties, Event, Resource>) -> Content
  ) throws {
    guard kind > 0, kind <= 65535, kind != 6, kind != 7, version > 0, capabilities.isValid
    else { throw BonsaiNativeViewError.invalidRegistration }
    guard definitions[kind] == nil else { throw BonsaiNativeViewError.duplicateKind(kind) }
    definitions[kind] = Self.definition(
      version: version, capabilities: capabilities, decode: decode,
      validateChildren: validateChildren,
      encodeEvent: encodeEvent, makeResource: makeResource, dispose: dispose, content: content)
  }

  func includingStandardViews() -> Self {
    var result = self
    result.definitions[6] = NativeMessageComposer.definition
    result.definitions[7] = NativeExpandableComposer.definition
    return result
  }

  static func definition<Properties, Event, Resource, Content: View>(
    version: UInt16, capabilities: BonsaiNativeCapabilities,
    decode: @escaping (Data) throws -> Properties,
    validateChildren: @escaping (Properties, Int) throws -> Void,
    encodeEvent: @escaping (Event) -> BonsaiNativeEvent,
    makeResource: @escaping () -> Resource, dispose: @escaping (Resource) -> Void,
    @ViewBuilder content: @escaping (BonsaiNativeContext<Properties, Event, Resource>) -> Content
  ) -> NativeViewDefinition {
    NativeViewDefinition(
      version: version, capabilities: capabilities,
      decode: { try decode($0) },
      validateChildren: { try validateChildren($0 as! Properties, $1) },
      makeResource: { makeResource() },
      dispose: { dispose($0 as! Resource) },
      content: { instance, children in
        let generation = instance.generation
        let context = BonsaiNativeContext(
          properties: instance.prepared.properties as! Properties,
          resource: instance.resource! as! Resource, children: children,
          isPresented: instance.isPresented,
          canInteract: { [weak instance] in
            guard let instance else { return false }
            return instance.accepts(generation) && instance.canInteract()
          },
          emit: { [weak instance] event in
            guard let instance, instance.accepts(generation) else { return false }
            let encoded = encodeEvent(event)
            guard encoded.id > 0, encoded.payload.count < ProtocolLimits.maxFrameBytes else {
              return false
            }
            return instance.emit(
              .nativeView(
                NativeViewEmission(
                  instance: instance.id, generation: generation,
                  kind: instance.prepared.envelope.kind, version: version,
                  event: encoded.id, payload: encoded.payload)))
          })
        return AnyView(content(context))
      })
  }

  func prepare(_ envelope: RenderNativeView) throws -> PreparedNativeView {
    guard let definition = definitions[envelope.kind]
    else { throw BonsaiNativeViewError.unregisteredKind(envelope.kind) }
    guard envelope.version == definition.version
    else { throw BonsaiNativeViewError.incompatibleVersion(envelope.kind, envelope.version) }
    guard envelope.capabilities.isSubset(of: definition.capabilities)
    else { throw BonsaiNativeViewError.unsupportedCapabilities(envelope.kind) }
    return PreparedNativeView(
      envelope: envelope, definition: definition,
      properties: try definition.decode(envelope.payload))
  }
}

struct RenderNativeView: Equatable, Sendable {
  let kind: UInt32
  let version: UInt16
  let capabilities: BonsaiNativeCapabilities
  let payload: Data
  static func decode(_ reader: inout WireReader) throws -> Self {
    let kind = try reader.integer(UInt32.self)
    let version = try reader.integer(UInt16.self)
    let capabilities = BonsaiNativeCapabilities(rawValue: try reader.integer(UInt64.self))
    guard kind > 0, kind <= 65535, version > 0, capabilities.isValid else {
      throw TreeError.invalidProperties
    }
    let count = Int(try reader.integer(UInt32.self))
    guard count <= ProtocolLimits.maxFrameBytes else { throw WireError.limitExceeded }
    return Self(
      kind: kind, version: version, capabilities: capabilities, payload: try reader.data(count))
  }
}
struct NativeViewEmission: Equatable, Sendable {
  let instance: UUID
  let generation: UInt64
  let kind: UInt32
  let version: UInt16
  let event: UInt16
  let payload: Data
}
@MainActor final class NativeViewDefinition {
  let version: UInt16
  let capabilities: BonsaiNativeCapabilities
  let decode: (Data) throws -> Any
  let validateChildren: (Any, Int) throws -> Void
  let makeResource: () -> Any
  let dispose: (Any) -> Void
  let content: (NativeViewInstance, [BonsaiNativeChild]) -> AnyView
  init(
    version: UInt16, capabilities: BonsaiNativeCapabilities, decode: @escaping (Data) throws -> Any,
    validateChildren: @escaping (Any, Int) throws -> Void,
    makeResource: @escaping () -> Any, dispose: @escaping (Any) -> Void,
    content: @escaping (NativeViewInstance, [BonsaiNativeChild]) -> AnyView
  ) {
    self.version = version
    self.capabilities = capabilities
    self.decode = decode
    self.validateChildren = validateChildren
    self.makeResource = makeResource
    self.dispose = dispose
    self.content = content
  }
}
@MainActor struct PreparedNativeView {
  let envelope: RenderNativeView
  let definition: NativeViewDefinition
  let properties: Any
}
@MainActor protocol NativeModalResource: AnyObject {
  var blocksBackgroundInput: Bool { get }
}

@MainActor @Observable final class NativeViewInstance {
  let id = UUID()
  var prepared: PreparedNativeView
  private(set) var generation: UInt64 = 0
  private(set) var isPresented = false
  private(set) var mounted = 0
  @ObservationIgnored private(set) var resource: Any?
  @ObservationIgnored private var childMounts: [RenderIdentity: Int] = [:]
  @ObservationIgnored private var bindings: [Int: UInt64]
  @ObservationIgnored private var children: [UInt64]
  @ObservationIgnored private(set) var disposed = false
  let emit: (NativeEventPayload) -> Bool
  var canInteract: () -> Bool = { false }
  var blocksBackgroundInput: Bool {
    (resource as? any NativeModalResource)?.blocksBackgroundInput ?? false
  }
  init(
    _ prepared: PreparedNativeView, node: RenderNode, emit: @escaping (NativeEventPayload) -> Bool
  ) {
    self.prepared = prepared
    self.emit = emit
    bindings = node.bindings
    children = node.children
    resource = prepared.definition.makeResource()
  }
  func synchronize(_ next: PreparedNativeView, node: RenderNode) {
    if prepared.envelope != next.envelope || bindings != node.bindings || children != node.children
    {
      prepared = next
      bindings = node.bindings
      children = node.children
      generation += 1
      setPresented(false)
    }
  }
  func accepts(_ generation: UInt64) -> Bool {
    !disposed && mounted > 0 && isPresented && self.generation == generation
  }
  func setPresented(_ value: Bool) {
    guard value != isPresented else { return }
    isPresented = value
    generation += 1
  }
  func mount() {
    guard !disposed else { return }
    mounted += 1
  }
  func unmount() {
    guard mounted > 0 else { return }
    mounted -= 1
    if mounted == 0 {
      generation += 1
      childMounts.removeAll()
    }
  }
  func mountChild(_ id: RenderIdentity) {
    guard !disposed else { return }
    childMounts[id, default: 0] += 1
  }
  func unmountChild(_ id: RenderIdentity) {
    if let count = childMounts[id] {
      if count <= 1 { childMounts.removeValue(forKey: id) } else { childMounts[id] = count - 1 }
    }
  }
  func containsMountedChild(_ id: RenderIdentity) -> Bool {
    accepts(generation) && (childMounts[id] ?? 0) > 0
  }
  func dispose() {
    guard !disposed else { return }
    disposed = true
    generation += 1
    isPresented = false
    childMounts.removeAll()
    if let resource { prepared.definition.dispose(resource) }
    resource = nil
  }
}
struct NativeRegisteredView: View {
  let instance: NativeViewInstance
  let children: [RenderNodeState]
  let activate: @MainActor (RenderNodeState) -> Void
  var body: some View {
    Group {
      if !instance.disposed {
        instance.prepared.definition.content(
          instance,
          children.map {
            BonsaiNativeChild(id: $0.id.node, node: $0, owner: instance, activate: activate)
          })
      }
    }
    .onAppear { instance.mount() }
    .onDisappear { instance.unmount() }
  }
}
