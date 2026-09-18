import Foundation
import Observation
import SwiftUI

struct RenderSwipeActions: Equatable, Sendable {
  let enabled: Bool
  let allowsFullSwipe: Bool
  static func decode(_ reader: inout WireReader) throws -> Self {
    Self(enabled: try reader.flag(), allowsFullSwipe: try reader.flag())
  }
}
struct RenderSwipeAction: Equatable, Sendable {
  let title: String
  let side: Int
  let enabled: Bool
  let role: Int
  let background: UInt32
  let symbol: String?
  static func decode(_ reader: inout WireReader) throws -> Self {
    let title = try reader.string()
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TreeError.invalidProperties
    }
    let side = try reader.choice(1)
    let enabled = try reader.flag()
    let role = try reader.choice(2)
    let background = try reader.integer(UInt32.self)
    let symbol = try reader.flag() ? reader.string() : nil
    guard symbol != "" else { throw TreeError.invalidProperties }
    return Self(
      title: title, side: side, enabled: enabled, role: role, background: background, symbol: symbol
    )
  }
}

// Own only event admission and settlement. SwiftUI owns all swipe interaction.
@MainActor @Observable final class SwipeActionsController {
  struct Request: Equatable {
    let serial: UInt64
    let action: RenderIdentity
  }
  let identity: RenderIdentity
  private(set) var properties: RenderSwipeActions
  private(set) var actions: [RenderNodeState] = []
  private(set) var generation: UInt64 = 0
  private(set) var pending: Request?
  @ObservationIgnored private(set) var dispatching: RenderIdentity?
  @ObservationIgnored private var serial: UInt64 = 0
  @ObservationIgnored private var disposed = false
  @ObservationIgnored private var active = true
  private struct Signature: Equatable {
    let id: RenderIdentity
    let properties: NodeProperties
    let bindings: [Int: UInt64]
  }
  private var signatures: [Signature] = []

  init(identity: RenderIdentity, properties: RenderSwipeActions) {
    self.identity = identity
    self.properties = properties
  }
  func items(_ side: Int) -> [RenderNodeState] {
    actions.filter {
      if case .swipeAction(let p) = $0.properties { return p.side == side }
      return false
    }
  }
  func synchronize(_ next: RenderSwipeActions, actions: [RenderNodeState]) {
    let signatures = actions.map {
      Signature(id: $0.id, properties: $0.properties, bindings: $0.bindings)
    }
    if next != properties || signatures != self.signatures { generation += 1 }
    self.signatures = signatures
    properties = next
    self.actions = actions
  }
  @discardableResult func perform(
    _ action: RenderNodeState, expected: RenderSwipeAction, generation: UInt64
  ) -> Bool {
    guard !disposed, active, generation == self.generation, properties.enabled, pending == nil,
      expected.enabled,
      actions.contains(where: { $0 === action }), action.properties == .swipeAction(expected)
    else { return false }
    dispatching = action.id
    let accepted = action.emit(.press)
    dispatching = nil
    guard accepted else { return false }
    serial &+= 1
    pending = Request(serial: serial, action: action.id)
    return true
  }
  func resolve(_ request: Request) { if pending == request { pending = nil } }
  func setActive(_ active: Bool) {
    if self.active && !active { generation &+= 1 }
    self.active = active
  }
  func dispose() {
    disposed = true
    pending = nil
    actions = []
  }
}

struct NativeSwipeActionsModifier: ViewModifier {
  let controller: SwipeActionsController
  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading, allowsFullSwipe: controller.properties.allowsFullSwipe) {
        actions(0)
      }
      .swipeActions(edge: .trailing, allowsFullSwipe: controller.properties.allowsFullSwipe) {
        actions(1)
      }
  }
  private func actions(_ side: Int) -> some View {
    ForEach(controller.items(side)) { action in
      NativeSwipeAction(node: action, controller: controller, activate: { _ in })
    }
  }
}
struct NativeSwipeAction: View {
  let node: RenderNodeState
  let controller: SwipeActionsController
  let activate: @MainActor (RenderNodeState) -> Void
  var body: some View {
    if case .swipeAction(let p) = node.properties {
      let generation = controller.generation
      Button(role: p.role == 2 ? .destructive : p.role == 1 ? .cancel : nil) {
        controller.perform(node, expected: p, generation: generation)
      } label: {
        if let symbol = p.symbol { Label(p.title, systemImage: symbol) } else { Text(p.title) }
      }
      .tint(
        Color(
          red: Double((p.background >> 16) & 255) / 255,
          green: Double((p.background >> 8) & 255) / 255,
          blue: Double(p.background & 255) / 255,
          opacity: Double(p.background >> 24) / 255)
      )
      .disabled(!p.enabled || !controller.properties.enabled)
      .accessibilityLabel(Text(verbatim: p.title))
    }
  }
}
