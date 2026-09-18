import Foundation
import Observation
import SwiftUI

struct RenderContextAction: Equatable, Sendable {
  let key: Data
  let title: String
  let enabled: Bool
  let role: Int
  let symbol: String?

  static func decode(_ reader: inout WireReader) throws -> Self {
    let key = Data(try reader.string().utf8)
    let title = try reader.string()
    let enabled = try reader.flag()
    let role = try reader.choice(1)
    let symbol = try reader.flag() ? reader.string() : nil
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, symbol != "" else {
      throw TreeError.invalidProperties
    }
    return Self(key: key, title: title, enabled: enabled, role: role, symbol: symbol)
  }
}

@MainActor @Observable final class ContextMenuController {
  struct Item: Identifiable {
    let node: RenderNodeState
    let properties: RenderContextAction
    let bindings: [Int: UInt64]
    var id: RenderIdentity { node.id }
  }
  struct Presentation {
    let owner: RenderIdentity
    let serial: UInt64
    let generation: UInt64
    let items: [Item]
  }
  let identity: RenderIdentity
  private(set) var enabled: Bool
  private(set) var actions: [RenderNodeState] = []
  @ObservationIgnored private(set) var dispatching: RenderIdentity?
  private struct Signature: Equatable {
    let identity: RenderIdentity
    let properties: NodeProperties
    let bindings: [Int: UInt64]
  }
  @ObservationIgnored private var signatures: [Signature] = []
  @ObservationIgnored private var generation: UInt64 = 0
  @ObservationIgnored private var serial: UInt64 = 0
  @ObservationIgnored private var consumed = true
  @ObservationIgnored private var active = true
  @ObservationIgnored private var disposed = false

  init(identity: RenderIdentity, enabled: Bool) {
    self.identity = identity
    self.enabled = enabled
  }
  func synchronize(enabled: Bool, actions: [RenderNodeState]) {
    let next = actions.map {
      Signature(identity: $0.id, properties: $0.properties, bindings: $0.bindings)
    }
    if enabled != self.enabled || next != signatures { generation &+= 1 }
    signatures = next
    self.enabled = enabled
    self.actions = actions
  }
  func capture() -> Presentation {
    serial &+= 1
    consumed = false
    return Presentation(
      owner: identity, serial: serial, generation: generation,
      items: actions.compactMap {
        guard case .contextAction(let properties) = $0.properties else { return nil }
        return Item(node: $0, properties: properties, bindings: $0.bindings)
      })
  }
  @discardableResult func perform(_ item: Item, from presentation: Presentation) -> Bool {
    guard !disposed, active, enabled, !consumed,
      presentation.owner == identity, presentation.serial == serial,
      presentation.generation == generation,
      item.properties.enabled,
      presentation.items.contains(where: {
        $0.node === item.node && $0.properties == item.properties && $0.bindings == item.bindings
      }),
      actions.contains(where: { $0 === item.node }),
      item.node.properties == .contextAction(item.properties), item.node.bindings == item.bindings
    else { return false }
    // Selecting a menu item consumes that presentation even if transport rejects it.
    consumed = true
    dispatching = item.id
    defer { dispatching = nil }
    return item.node.emit(.press)
  }
  var isAvailable: Bool { !disposed && active && enabled && !actions.isEmpty }
  func invalidatePresentation() { generation &+= 1 }

  func setActive(_ active: Bool) {
    if self.active && !active { generation &+= 1 }
    self.active = active
  }
  func dispose() {
    disposed = true
    generation &+= 1
    actions = []
    signatures = []
  }
}

struct NativeContextMenuModifier: ViewModifier {
  let controller: ContextMenuController
  func body(content: Content) -> some View {
    content.background(NativeContextMenuAnchor(controller: controller))
  }
}

struct NativeContextMenuContent: View {
  let controller: ContextMenuController
  let presentation: ContextMenuController.Presentation
  var body: some View {
    ForEach(presentation.items) { item in
      Button(role: item.properties.role == 1 ? .destructive : nil) {
        controller.perform(item, from: presentation)
      } label: {
        if let symbol = item.properties.symbol {
          Label(item.properties.title, systemImage: symbol)
        } else {
          Text(verbatim: item.properties.title)
        }
      }.disabled(!item.properties.enabled)
    }
  }
}
