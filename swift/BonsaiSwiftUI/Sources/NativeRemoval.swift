import Observation
import SwiftUI

struct RenderRemoval: Equatable, Sendable {
  let token: Int64
  let state: Int
  let vertical: Bool
  let collapseVertical: Bool
  let title: String
  let milliseconds: UInt32
  static func decode(_ reader: inout WireReader) throws -> Self {
    let token = try Int64(bitPattern: reader.integer(UInt64.self))
    let state = try reader.choice(3)
    let vertical = try reader.flag()
    let collapse = try reader.flag()
    let title = try reader.string()
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TreeError.invalidProperties
    }
    return Self(
      token: token, state: state, vertical: vertical, collapseVertical: collapse,
      title: title, milliseconds: try reader.integer(UInt32.self))
  }
}

@MainActor @Observable final class RemovalController: NativePanTarget {
  private(set) var properties: RenderRemoval
  private(set) var value = AnimatablePair(1.0, 0.0)
  private(set) var offset = 0.0
  private(set) var generation: UInt64 = 0
  private(set) var dispatching = false
  private var waiting = false
  private var consumed: Int64?
  private var dragging = false
  private var size = CGSize.zero
  private var rtl = false
  private var reducedMotion = false
  private var presented = false
  private var active = false
  private var mounted = 0
  private var disposed = false
  private var completionPending = false
  private var running = false
  private var ready = false
  @ObservationIgnored private let emit: (NativeEventPayload) -> Bool

  init(_ properties: RenderRemoval, emit: @escaping (NativeEventPayload) -> Bool) {
    self.properties = properties
    self.emit = emit
    if properties.state == 2 {
      value.first = 0
      completionPending = true
      ready = true
    }
  }
  var busy: Bool { waiting || properties.state == 1 }
  var blocksContent: Bool { busy || properties.state == 2 || dragging || offset != 0 }
  var canRequest: Bool {
    !disposed && active && presented && mounted > 0 && !busy
      && (properties.state == 0 || properties.state == 3) && consumed != properties.token
  }
  var length: Double { properties.vertical ? size.height : size.width }
  var physicalOffset: Double { properties.vertical || !rtl ? offset : -offset }
  var defaultDirection: Int64 { properties.vertical ? 2 : 1 }
  func synchronize(_ next: RenderRemoval) {
    guard !disposed, properties != next else { return }
    let replaced = properties.token != next.token
    if replaced {
      consumed = nil
      waiting = false
      offset = 0
    }
    generation += 1
    running = false
    ready = false
    dragging = false
    properties = next
    if next.state == 2 {
      waiting = false
      completionPending = true
    } else {
      completionPending = false
      value = AnimatablePair(1, 1 - value.second)
      if next.state == 3 || replaced {
        waiting = false
        settle(0)
      }
    }
    presented = false
  }
  func invalidateBinding() {
    generation += 1
    waiting = false
    dragging = false
    offset = 0
    presented = false
    running = false
  }
  func attach() {
    mounted += 1
    advance()
  }
  func detach() {
    mounted = max(0, mounted - 1)
    if mounted == 0 {
      snap()
      waiting = false
      offset = 0
      dragging = false
    }
  }
  func configure(size: CGSize, rtl: Bool, reducedMotion: Bool) {
    if self.size != size || self.rtl != rtl {
      dragging = false
      offset = 0
    }
    self.size = size
    self.rtl = rtl
    self.reducedMotion = reducedMotion
    if reducedMotion && running { snap() }
    advance()
  }
  func setPresentation(presented: Bool, active: Bool) {
    self.presented = presented && !disposed
    self.active = active && !disposed
    if !active {
      snap()
      dragging = false
      waiting = false
      offset = 0
    }
    advance()
  }
  private func settle(_ offset: Double) {
    withAnimation(reducedMotion || !active ? .linear(duration: 0) : .easeOut(duration: 0.18)) {
      self.offset = offset
    }
  }
  func canBegin(_ translation: CGSize) -> Bool {
    guard canRequest, length > 0, translation.width.isFinite, translation.height.isFinite else {
      return false
    }
    let main = properties.vertical ? translation.height : translation.width
    let cross = properties.vertical ? translation.width : translation.height
    return abs(main) >= 4 && abs(main) > abs(cross) * 1.25
  }
  func begin() { if canRequest { dragging = true } }
  func change(_ translation: CGSize) {
    guard dragging, translation.width.isFinite, translation.height.isFinite else { return }
    let main = properties.vertical ? translation.height : translation.width
    offset = min(length, max(-length, properties.vertical || !rtl ? main : -main))
  }
  func end(cancelled: Bool) {
    guard dragging else { return }
    dragging = false
    guard !cancelled, abs(offset) >= max(44, length * 0.45) else {
      settle(0)
      return
    }
    let direction: Int64 = properties.vertical ? (offset > 0 ? 3 : 2) : (offset > 0 ? 0 : 1)
    if !request(direction: direction, generation: generation) { settle(0) }
  }
  @discardableResult func request(direction: Int64, generation expected: UInt64) -> Bool {
    guard expected == generation, canRequest,
      properties.vertical ? (2...3).contains(direction) : (0...1).contains(direction)
    else { return false }
    dispatching = true
    let accepted = emit(.removalRequested(token: properties.token, direction: direction))
    dispatching = false
    guard accepted else { return false }
    consumed = properties.token
    waiting = true
    settle((direction == 0 || direction == 3 ? 1 : -1) * min(72, length * 0.25))
    return true
  }
  func canComplete(_ token: Int64) -> Bool {
    !disposed && active && presented && mounted > 0 && properties.token == token
      && properties.state == 2 && completionPending && ready
  }
  private func snap() {
    guard completionPending else { return }
    generation += 1
    running = false
    ready = true
    withAnimation(.linear(duration: 0)) { value = AnimatablePair(0, 1 - value.second) }
  }
  private func advance() {
    guard !disposed, active, presented, mounted > 0, completionPending else { return }
    if ready {
      if emit(.removalCompleted(properties.token)) {
        completionPending = false
        ready = false
      }
      return
    }
    guard !running else { return }
    running = true
    let expected = generation
    let duration = reducedMotion ? 0 : Double(properties.milliseconds) / 1000
    withAnimation(.easeInOut(duration: duration), completionCriteria: .removed) {
      value = AnimatablePair(0, 1 - value.second)
    } completion: { [weak self] in
      Task { @MainActor in
        guard let self, self.generation == expected, !self.disposed, self.completionPending else {
          return
        }
        self.running = false
        self.ready = true
        self.advance()
      }
    }
  }
  func dispose() {
    disposed = true
    generation += 1
    waiting = false
    dragging = false
    running = false
    ready = false
    completionPending = false
  }
}

private struct RemovalLayout: Layout {
  let vertical: Bool
  var value: AnimatablePair<Double, Double>
  var animatableData: AnimatablePair<Double, Double> {
    get { value }
    set { value = newValue }
  }
  private func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
    ProposedViewSize(
      width: vertical ? proposal.width : nil, height: vertical ? nil : proposal.height)
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let size = subviews[0].sizeThatFits(childProposal(proposal))
    let fraction = min(1, max(0, value.first))
    return CGSize(
      width: vertical ? size.width : size.width * fraction,
      height: vertical ? size.height * fraction : size.height)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: childProposal(proposal))
  }
}

struct NativeRemoval: View {
  let node: RenderNodeState
  let controller: RemovalController
  let activate: @MainActor (RenderNodeState) -> Void
  @Environment(\.layoutDirection) private var direction
  @Environment(\.accessibilityReduceMotion) private var reducedMotion
  @State private var size = CGSize.zero
  var body: some View {
    let generation = controller.generation
    let properties = controller.properties
    return RemovalLayout(vertical: properties.collapseVertical, value: controller.value) {
      NativeNodeView(node: node.children[0], activate: activate)
        .allowsHitTesting(!controller.blocksContent).disabled(controller.blocksContent)
        .onGeometryChange(for: CGSize.self) {
          $0.size
        } action: { size in
          self.size = size
          configure()
        }
        .offset(
          x: properties.vertical ? 0 : controller.physicalOffset,
          y: properties.vertical ? controller.physicalOffset : 0
        )
        .opacity(controller.value.first)
        .overlay { if controller.busy { ProgressView().accessibilityLabel("Waiting for removal") } }
    }
    .clipped().contentShape(Rectangle())
    .gesture(NativeSwipePan(controller: controller))
    .accessibilityElement(children: .contain)
    .accessibilityHidden(properties.state == 2)
    .accessibilityActions {
      if controller.canRequest {
        Button(properties.title) {
          controller.request(direction: controller.defaultDirection, generation: generation)
        }
      }
    }
    .contextMenu {
      if controller.canRequest {
        Button(properties.title, role: .destructive) {
          controller.request(direction: controller.defaultDirection, generation: generation)
        }
      }
    }
    .onAppear {
      configure()
      controller.attach()
    }
    .onDisappear { controller.detach() }
    .onChange(of: direction) { _, _ in configure() }
    .onChange(of: reducedMotion) { _, _ in configure() }
  }
  private func configure() {
    controller.configure(size: size, rtl: direction == .rightToLeft, reducedMotion: reducedMotion)
  }
}
