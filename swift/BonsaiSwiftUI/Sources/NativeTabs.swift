import Observation
import SwiftUI

struct RenderTabKey: Hashable, Sendable {
  let value: String
  var bytes: Data { Data(value.utf8) }
  init(_ value: String) { self.value = value }
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }
  func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
  static func decode(_ reader: inout WireReader) throws -> Self {
    let value = try reader.string()
    guard !value.isEmpty else { throw TreeError.invalidProperties }
    return Self(value)
  }
}

struct RenderTab: Equatable, Sendable {
  let key: RenderTabKey
  let title: String
  let symbol: String
  let badge: String?
  let accessibilityLabel: String?
  static func decode(_ reader: inout WireReader) throws -> Self {
    let key = try RenderTabKey.decode(&reader)
    let title = try reader.string()
    let symbol = try reader.string()
    guard !symbol.isEmpty else { throw TreeError.invalidProperties }
    let badge = try reader.flag() ? reader.string() : nil
    let accessibilityLabel = try reader.flag() ? reader.string() : nil
    for value in [badge, accessibilityLabel].compactMap({ $0 }) {
      guard value.utf8.contains(where: { ![9, 10, 12, 13, 32].contains($0) }) else {
        throw TreeError.invalidProperties
      }
    }
    return Self(
      key: key, title: title, symbol: symbol, badge: badge, accessibilityLabel: accessibilityLabel)
  }
}

@MainActor @Observable final class TabsController {
  struct Request: Equatable {
    let serial: UInt64
    let key: RenderTabKey
  }
  private(set) var selection: RenderTabKey
  private(set) var pending: Request?
  private var authoritative: RenderTabKey
  private var options: [RenderTabKey: RenderIdentity] = [:]
  private var generation: UInt64 = 0
  private var serial: UInt64 = 0
  private var disposed = false

  init(_ selection: RenderTabKey) {
    self.selection = selection
    authoritative = selection
  }
  func synchronize(_ next: RenderTabKey, children: [RenderNodeState]) {
    let options = Dictionary(
      uniqueKeysWithValues: children.map { node in
        guard case .tab(let tab) = node.properties else { preconditionFailure("Invalid tab child") }
        return (tab.key, node.id)
      })
    authoritative = next
    let visible: RenderTabKey
    if let pending, options[pending.key] != nil, options[pending.key] == self.options[pending.key] {
      visible = pending.key
    } else {
      pending = nil
      visible = next
    }
    if visible != selection || options != self.options { generation += 1 }
    selection = visible
    self.options = options
  }
  func resolve(_ request: Request) {
    guard pending == request else { return }
    pending = nil
    if selection != authoritative { generation += 1 }
    selection = authoritative
  }
  @discardableResult func request(_ next: RenderTabKey, emit: (NativeEventPayload) -> Bool) -> Bool
  {
    guard !disposed, options[next] != nil, next != selection, emit(.tabSelection(next)) else {
      return false
    }
    serial += 1
    pending = Request(serial: serial, key: next)
    selection = next
    return true
  }
  private final class BindingRead {
    var generation: UInt64
    init(_ generation: UInt64) { self.generation = generation }
  }
  func binding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<RenderTabKey> {
    let read = BindingRead(generation)
    return Binding(
      get: {
        read.generation = self.generation
        return self.selection
      },
      set: { next in
        guard read.generation == self.generation else { return }
        self.request(next, emit: emit)
      })
  }
  func dispose() {
    disposed = true
    pending = nil
    generation += 1
  }
}

struct NativeTabs: View {
  let node: RenderNodeState
  let controller: TabsController
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    TabView(selection: controller.binding(emit: node.emit)) {
      ForEach(node.children) { child in
        if case .tab(let tab) = child.properties {
          Tab(value: tab.key) {
            NativeNodeView(node: child, activate: activate)
          } label: {
            Label {
              Text(verbatim: tab.title)
            } icon: {
              Image(systemName: tab.symbol)
            }
          }
          .badge(tab.badge.map { Text(verbatim: $0) })
          .accessibilityLabel(
            Text(verbatim: tab.accessibilityLabel ?? ""),
            isEnabled: tab.accessibilityLabel != nil)
        }
      }
    }
  }
}
