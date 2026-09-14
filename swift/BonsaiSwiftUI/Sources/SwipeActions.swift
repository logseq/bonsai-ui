import Foundation
import Observation
import SwiftUI

struct RenderSwipeActions: Equatable, Sendable {
  let enabled: Bool
  let vertical: Bool
  let closeOnScroll: Bool
  let group: Data?
  let closeWhenOpened: Bool
  let closeWhenTapped: Bool
  static func decode(_ reader: inout WireReader) throws -> Self {
    let enabled = try reader.flag()
    let vertical = try reader.flag()
    let closeOnScroll = try reader.flag()
    let group = try reader.flag() ? reader.string() : nil
    guard group != "" else { throw TreeError.invalidProperties }
    return Self(
      enabled: enabled, vertical: vertical, closeOnScroll: closeOnScroll,
      group: group.map { Data($0.utf8) }, closeWhenOpened: try reader.flag(),
      closeWhenTapped: try reader.flag())
  }
}
struct RenderSwipeAction: Equatable, Sendable {
  let title: String
  let side: Int
  let enabled: Bool
  let role: Int
  let extent: Double
  let background: UInt32
  let autoClose: Bool
  let fullSwipe: Bool
  static func decode(_ reader: inout WireReader) throws -> Self {
    let title = try reader.string()
    guard !title.isEmpty else { throw TreeError.invalidProperties }
    let side = try reader.choice(1)
    let enabled = try reader.flag()
    let role = try reader.choice(2)
    let extent = try reader.finiteDouble()
    guard extent >= 44, extent <= 4096 else { throw TreeError.invalidProperties }
    return Self(
      title: title, side: side, enabled: enabled, role: role, extent: extent,
      background: try reader.integer(UInt32.self), autoClose: try reader.flag(),
      fullSwipe: try reader.flag())
  }
}

@MainActor @Observable final class SwipeActionsController {
  struct Request: Equatable {
    let serial: UInt64
    let action: RenderIdentity
  }
  let identity: RenderIdentity
  private(set) var properties: RenderSwipeActions
  private(set) var actions: [RenderNodeState] = []
  private(set) var offset: Double = 0
  private(set) var size: CGSize = .zero
  private(set) var pending: Request?
  private(set) var dragging = false
  @ObservationIgnored private(set) var dispatching: RenderIdentity?
  @ObservationIgnored var onOpen: ((SwipeActionsController) -> Void)?
  @ObservationIgnored private var serial: UInt64 = 0
  @ObservationIgnored private var origin = 0.0
  @ObservationIgnored private var rtl = false
  @ObservationIgnored private var reducedMotion = false
  @ObservationIgnored private var active = true
  @ObservationIgnored private var disposed = false
  @ObservationIgnored private var signatures: [Signature] = []
  private struct Signature: Equatable {
    let identity: RenderIdentity
    let properties: NodeProperties
    let bindings: [Int: UInt64]
  }

  init(identity: RenderIdentity, properties: RenderSwipeActions) {
    self.identity = identity
    self.properties = properties
  }
  var length: Double { properties.vertical ? size.height : size.width }
  var physicalOffset: Double { properties.vertical || !rtl ? offset : -offset }
  func items(_ side: Int) -> [RenderNodeState] {
    actions.filter {
      if case .swipeAction(let p) = $0.properties { return p.side == side }
      return false
    }
  }
  func extent(_ side: Int) -> Double {
    min(
      length * 0.8,
      items(side).reduce(0) {
        guard case .swipeAction(let p) = $1.properties else { return $0 }
        return $0 + p.extent
      })
  }
  func exposed(_ side: Int) -> Bool { side == 0 ? offset > 0 : offset < 0 }
  func synchronize(_ next: RenderSwipeActions, actions: [RenderNodeState]) {
    let signatures = actions.map {
      Signature(identity: $0.id, properties: $0.properties, bindings: $0.bindings)
    }
    if properties != next || self.signatures != signatures {
      close(animated: false)
      pending = nil
    }
    properties = next
    self.actions = actions
    self.signatures = signatures
  }
  func configure(size: CGSize, rtl: Bool, reducedMotion: Bool, active: Bool) {
    let previousLength = length
    self.size = size
    if self.rtl != rtl || previousLength != length || !active { close(animated: false) }
    self.rtl = rtl
    self.reducedMotion = reducedMotion
    self.active = active
  }
  func open(_ side: Int) {
    guard !disposed, active, properties.enabled, pending == nil, extent(side) > 0 else { return }
    onOpen?(self)
    settle((side == 0 ? 1 : -1) * extent(side))
  }
  func close(animated: Bool = true) {
    dragging = false
    if animated { settle(0) } else { offset = 0 }
  }
  private func settle(_ target: Double) {
    if reducedMotion || !active {
      offset = target
    } else {
      withAnimation(.easeOut(duration: 0.18)) { offset = target }
    }
  }
  func canBegin(_ translation: CGSize) -> Bool {
    guard !disposed, active, properties.enabled, pending == nil, length > 0 else { return false }
    let primary = properties.vertical ? translation.height : translation.width
    let cross = properties.vertical ? translation.width : translation.height
    guard abs(primary) >= 4, abs(primary) > abs(cross) * 1.25 else { return false }
    let logical = properties.vertical || !rtl ? primary : -primary
    return offset != 0 || !items(logical > 0 ? 0 : 1).isEmpty
  }
  func begin() {
    guard !disposed, active, properties.enabled, pending == nil else { return }
    origin = offset
    dragging = true
    onOpen?(self)
  }
  func change(_ translation: CGSize) {
    guard dragging, !disposed, active, properties.enabled else { return }
    let physical = properties.vertical ? translation.height : translation.width
    let value = origin + (properties.vertical || !rtl ? physical : -physical)
    let side = value >= 0 ? 0 : 1
    let maximum = fullAction(side) == nil ? extent(side) : length
    offset = (side == 0 ? 1 : -1) * min(abs(value), maximum)
  }
  private func fullAction(_ side: Int) -> RenderNodeState? {
    items(side).first {
      if case .swipeAction(let p) = $0.properties { return p.fullSwipe && p.enabled }
      return false
    }
  }
  func end(cancelled: Bool) {
    guard dragging else { return }
    dragging = false
    if cancelled {
      settle(origin)
      return
    }
    let side = offset >= 0 ? 0 : 1
    let threshold = min(length * 0.9, max(length * 0.72, extent(side) + 44))
    if abs(offset) >= threshold, let action = fullAction(side),
      case .swipeAction(let p) = action.properties
    {
      if !perform(action, expected: p, requireReveal: true) { settle(0) }
    } else {
      settle(abs(offset) >= extent(side) * 0.5 ? (side == 0 ? 1 : -1) * extent(side) : 0)
    }
  }
  @discardableResult func perform(
    _ action: RenderNodeState, expected: RenderSwipeAction, requireReveal: Bool
  ) -> Bool {
    guard !disposed, active, properties.enabled, pending == nil, expected.enabled,
      actions.contains(where: { $0 === action }), action.properties == .swipeAction(expected),
      !requireReveal || exposed(expected.side)
    else { return false }
    dispatching = action.id
    let accepted = action.emit(.press)
    dispatching = nil
    guard accepted else { return false }
    serial &+= 1
    pending = Request(serial: serial, action: action.id)
    if expected.autoClose { close() }
    return true
  }
  func resolve(_ request: Request) { if pending == request { pending = nil } }
  func dispose() {
    disposed = true
    pending = nil
    close(animated: false)
    onOpen = nil
    actions = []
  }
}

private struct SwipeScrollActivityKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
  var bonsaiScrollIsActive: Bool {
    get { self[SwipeScrollActivityKey.self] }
    set { self[SwipeScrollActivityKey.self] = newValue }
  }
}
struct SwipeScrollActivity: ViewModifier {
  @State private var active = false
  func body(content: Content) -> some View {
    content.environment(\.bonsaiScrollIsActive, active)
      .onScrollPhaseChange { _, phase in active = phase != .idle }
  }
}

struct NativeSwipeActions: View {
  @Environment(\.layoutDirection) private var direction
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.bonsaiScrollIsActive) private var scrolling
  let node: RenderNodeState
  let controller: SwipeActionsController
  let activate: @MainActor (RenderNodeState) -> Void
  private var vertical: Bool { controller.properties.vertical }
  private var open: Bool { controller.offset != 0 }

  var body: some View {
    NativeNodeView(node: node.children[0], activate: activate)
      .allowsHitTesting(!open).disabled(open)
      .overlay {
        if open { Color.clear.contentShape(Rectangle()).onTapGesture { controller.close() } }
      }
      .offset(
        x: vertical ? 0 : controller.physicalOffset, y: vertical ? controller.physicalOffset : 0
      )
      .background {
        GeometryReader { geometry in
          ZStack(alignment: .topLeading) {
            if controller.exposed(0) { pane(0, in: geometry.size) }
            if controller.exposed(1) { pane(1, in: geometry.size) }
          }
        }
      }
      .clipped().contentShape(Rectangle())
      .gesture(NativeSwipePan(controller: controller))
      .onGeometryChange(for: CGSize.self) {
        $0.size
      } action: { size in
        configure(size)
      }
      .onChange(of: direction) { _, _ in configure(controller.size) }
      .onChange(of: reduceMotion) { _, _ in configure(controller.size) }
      .onChange(of: scenePhase) { _, _ in configure(controller.size) }
      .onChange(of: node.progressAnimationsActive) { _, _ in configure(controller.size) }
      .onChange(of: scrolling) { _, value in
        if value && controller.properties.closeOnScroll { controller.close() }
      }
      .onDisappear { controller.close(animated: false) }
      .accessibilityElement(children: .contain)
      .accessibilityActions {
        if controller.properties.enabled {
          ForEach(controller.actions) { action in
            if case .swipeAction(let p) = action.properties, p.enabled {
              Button(p.title) { controller.perform(action, expected: p, requireReveal: false) }
            }
          }
          if !controller.items(0).isEmpty {
            Button(vertical ? "Show top actions" : "Show leading actions") { controller.open(0) }
          }
          if !controller.items(1).isEmpty {
            Button(vertical ? "Show bottom actions" : "Show trailing actions") {
              controller.open(1)
            }
          }
          if open { Button("Close actions") { controller.close() } }
        }
      }
      .contextMenu {
        ForEach(controller.actions) { action in
          if case .swipeAction(let p) = action.properties {
            Button(p.title, role: p.role == 2 ? .destructive : p.role == 1 ? .cancel : nil) {
              controller.perform(action, expected: p, requireReveal: false)
            }.disabled(!p.enabled || !controller.properties.enabled)
          }
        }
      }
  }
  private func configure(_ size: CGSize) {
    controller.configure(
      size: size, rtl: direction == .rightToLeft, reducedMotion: reduceMotion,
      active: scenePhase == .active && node.progressAnimationsActive)
  }
  private func pane(_ side: Int, in size: CGSize) -> some View {
    let extent = controller.extent(side)
    let actions = controller.items(side)
    let total = actions.reduce(0.0) { result, action in
      if case .swipeAction(let properties) = action.properties { return result + properties.extent }
      return result
    }
    let alignment: Alignment =
      vertical ? (side == 0 ? .top : .bottom) : (side == 0 ? .leading : .trailing)
    let layout =
      vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
    return layout {
      ForEach(actions) { action in
        if case .swipeAction(let properties) = action.properties {
          let actionExtent = extent * properties.extent / max(total, 1)
          NativeSwipeAction(node: action, controller: controller, activate: activate)
            .frame(
              width: vertical ? size.width : actionExtent,
              height: vertical ? actionExtent : size.height)
        }
      }
    }
    .frame(width: vertical ? size.width : extent, height: vertical ? extent : size.height)
    .frame(width: size.width, height: size.height, alignment: alignment)
  }
}
struct NativeSwipeAction: View {
  let node: RenderNodeState
  let controller: SwipeActionsController
  let activate: @MainActor (RenderNodeState) -> Void
  var body: some View {
    if case .swipeAction(let p) = node.properties {
      Button(role: p.role == 2 ? .destructive : p.role == 1 ? .cancel : nil) {
        controller.perform(node, expected: p, requireReveal: true)
      } label: {
        NativeNodeView(node: node.children[0], activate: activate)
          .allowsHitTesting(false)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .foregroundStyle(.white)
          .background(
            Color(
              red: Double((p.background >> 16) & 255) / 255,
              green: Double((p.background >> 8) & 255) / 255,
              blue: Double(p.background & 255) / 255,
              opacity: Double(p.background >> 24) / 255))
      }
      .buttonStyle(.plain).disabled(!p.enabled || !controller.properties.enabled)
      .accessibilityLabel(Text(verbatim: p.title))
    }
  }
}
