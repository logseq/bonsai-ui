import Observation
import SwiftUI

struct RenderMenu: Equatable, Sendable {
  struct Entry: Equatable, Identifiable, Sendable {
    let id: Int64
    let kind: Int
    let enabled: Bool
    let selected: Bool
    let role: Int
    let labelIndex: Int?
    let children: [Entry]
    func sameConfiguration(as other: Self) -> Bool {
      id == other.id && kind == other.kind && enabled == other.enabled && role == other.role
        && labelIndex == other.labelIndex && children.count == other.children.count
        && zip(children, other.children).allSatisfy { $0.sameConfiguration(as: $1) }
    }
  }
  let entries: [Entry]
  let enabled: Bool
  let labelCount: Int
  let byID: [Int64: Entry]
  let selectable: Set<Int64>
  func admits(_ id: Int64) -> Bool { enabled && selectable.contains(id) }
  func sameConfiguration(as other: Self) -> Bool {
    enabled == other.enabled && labelCount == other.labelCount
      && entries.count == other.entries.count
      && zip(entries, other.entries).allSatisfy { $0.sameConfiguration(as: $1) }
  }
  static func decode(_ reader: inout WireReader) throws -> Self {
    let count = Int(try reader.integer(UInt16.self))
    guard count > 0, count <= 1024 else { throw TreeError.invalidProperties }
    var consumed = 0
    var labels = 1
    var ids = Set<Int64>()
    var byID: [Int64: Entry] = [:]
    var selectable = Set<Int64>()
    func read(_ reader: inout WireReader, depth: Int, active: Bool) throws -> Entry {
      guard depth <= 32, consumed < count else { throw TreeError.invalidProperties }
      consumed += 1
      let id = Int64(bitPattern: try reader.integer(UInt64.self))
      guard ids.insert(id).inserted else { throw TreeError.invalidProperties }
      let kind = try reader.choice(4)
      let enabled = try reader.flag()
      let selected = try reader.flag()
      let role = try reader.choice(2)
      let hasLabel = try reader.flag()
      let childrenCount = Int(try reader.integer(UInt16.self))
      guard role == 0 || kind == 0, !selected || kind == 1,
        kind != 2 || (!enabled && !hasLabel), kind != 3 || enabled,
        ![0, 1, 4].contains(kind) || hasLabel,
        kind < 3 ? childrenCount == 0 : childrenCount > 0, childrenCount <= count - consumed
      else { throw TreeError.invalidProperties }
      let labelIndex = hasLabel ? labels : nil
      if hasLabel { labels += 1 }
      var children: [Entry] = []
      for _ in 0..<childrenCount {
        children.append(try read(&reader, depth: depth + 1, active: active && enabled))
      }
      let entry = Entry(
        id: id, kind: kind, enabled: enabled, selected: selected, role: role,
        labelIndex: labelIndex, children: children)
      byID[id] = entry
      if kind <= 1 && active && enabled { selectable.insert(id) }
      return entry
    }
    var entries: [Entry] = []
    while consumed < count { entries.append(try read(&reader, depth: 1, active: true)) }
    return Self(
      entries: entries, enabled: try reader.flag(), labelCount: labels, byID: byID,
      selectable: selectable)
  }
}

@MainActor @Observable final class NativeMenuController {
  struct Request: Equatable {
    let serial: UInt64
    let id: Int64
    let selected: Bool?
  }
  private(set) var pending: [Request] = []
  private var properties: RenderMenu
  private var serial: UInt64 = 0
  private var generation: UInt64 = 0
  private var disposed = false
  init(_ properties: RenderMenu) { self.properties = properties }
  func synchronize(_ next: RenderMenu) {
    if !next.sameConfiguration(as: properties) { invalidateBinding() }
    properties = next
  }
  func invalidateBinding() {
    pending.removeAll()
    generation += 1
  }
  @discardableResult func select(_ id: Int64, emit: (NativeEventPayload) -> Bool) -> Bool {
    guard !disposed, properties.admits(id) else { return false }
    guard emit(.menuAction(id)) else {
      generation += 1
      return false
    }
    serial += 1
    pending.append(
      Request(serial: serial, id: id, selected: properties.byID[id]?.kind == 1 ? !checked(id) : nil)
    )
    return true
  }
  func action(_ id: Int64, emit: @escaping (NativeEventPayload) -> Bool) -> () -> Void {
    let generation = generation
    return {
      guard generation == self.generation else { return }
      self.select(id, emit: emit)
    }
  }
  func checked(_ id: Int64) -> Bool {
    pending.last(where: { $0.id == id })?.selected ?? properties.byID[id]?.selected ?? false
  }
  func resolve(_ request: Request) {
    pending.removeAll { $0.serial <= request.serial }
  }
  func dispose() {
    disposed = true
    invalidateBinding()
  }
}

struct NativeMenu: View {
  let node: RenderNodeState
  let properties: RenderMenu
  let controller: NativeMenuController
  let activate: @MainActor (RenderNodeState) -> Void
  private func label(_ index: Int) -> some View {
    NativeNodeView(node: node.children[index], activate: activate).allowsHitTesting(false)
  }
  private func items(_ entries: [RenderMenu.Entry], enabled: Bool) -> some View {
    ForEach(entries) { entry in item(entry, enabled: enabled && entry.enabled) }
  }
  private func item(_ entry: RenderMenu.Entry, enabled: Bool) -> AnyView {
    switch entry.kind {
    case 0:
      return AnyView(
        Button(
          role: entry.role == 1 ? .cancel : entry.role == 2 ? .destructive : nil,
          action: controller.action(entry.id, emit: node.emit)
        ) { label(entry.labelIndex!) }.disabled(!enabled))
    case 1:
      let action = controller.action(entry.id, emit: node.emit)
      return AnyView(
        Toggle(isOn: Binding(get: { controller.checked(entry.id) }, set: { _ in action() })) {
          label(entry.labelIndex!)
        }.disabled(!enabled))
    case 2: return AnyView(Divider())
    case 3:
      return AnyView(
        Section {
          items(entry.children, enabled: enabled)
        } header: {
          if let index = entry.labelIndex { label(index) }
        })
    case 4:
      return AnyView(
        Menu {
          items(entry.children, enabled: enabled)
        } label: {
          label(entry.labelIndex!)
        }.disabled(!enabled))
    default: preconditionFailure("Unvalidated menu kind")
    }
  }
  var body: some View {
    Menu {
      items(properties.entries, enabled: properties.enabled)
    } label: {
      label(0)
    }.disabled(!properties.enabled)
  }
}
