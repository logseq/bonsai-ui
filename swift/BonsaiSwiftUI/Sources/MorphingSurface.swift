import Foundation
import Observation
import SwiftUI

struct RenderMorphingSurface: Equatable, Sendable {
  let expanded: Bool
  let expandMilliseconds: UInt32
  let collapseMilliseconds: UInt32

  static func decode(_ reader: inout WireReader) throws -> Self {
    Self(
      expanded: try reader.flag(), expandMilliseconds: try reader.integer(UInt32.self),
      collapseMilliseconds: try reader.integer(UInt32.self))
  }
}

@MainActor @Observable
final class MorphingSurfaceController {
  private(set) var progress: Double
  private(set) var animationID: UInt64 = 0
  @ObservationIgnored private var properties: RenderMorphingSurface
  @ObservationIgnored private var mounted = 0
  @ObservationIgnored private var active = true
  @ObservationIgnored private var reducedMotion = false
  @ObservationIgnored private var disposed = false
  @ObservationIgnored private var transition: Transition?

  private struct Transition {
    let from: Double
    let target: Double
    let started: Double
    let duration: Double
    func sample(_ now: Double) -> Double {
      let t = min(1, max(0, (now - started) / duration))
      let curve =
        target > from
        ? 1 - pow(1 - t, 3)
        : t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
      return from + (target - from) * curve
    }
  }
  private var now: Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }

  init(_ properties: RenderMorphingSurface) {
    self.properties = properties
    progress = properties.expanded ? 1 : 0
  }
  func replace(_ next: RenderMorphingSurface) {
    let changed = properties.expanded != next.expanded
    properties = next
    guard changed, !disposed else { return }
    let time = now
    // Retarget from the last published visual value, without advancing the old animation.
    let from = progress
    let target = next.expanded ? 1.0 : 0.0
    let duration =
      Double(next.expanded ? next.expandMilliseconds : next.collapseMilliseconds) / 1000
    guard mounted > 0, active, !reducedMotion, duration > 0, from != target else {
      finish()
      return
    }
    progress = from
    transition = Transition(from: from, target: target, started: time, duration: duration)
    animationID &+= 1
  }
  func attach() { mounted += 1 }
  func detach() {
    mounted = max(0, mounted - 1)
    if mounted == 0 { finish() }
  }
  func setAnimationsActive(_ value: Bool) {
    active = value
    if !value { finish() }
  }
  func setReducedMotion(_ value: Bool) {
    reducedMotion = value
    if value { finish() }
  }
  func dispose() {
    disposed = true
    finish()
  }
  private func finish() {
    if transition != nil { animationID &+= 1 }
    transition = nil
    progress = properties.expanded ? 1 : 0
  }
  func runAnimation(_ id: UInt64) async {
    while !Task.isCancelled, !disposed, id == animationID, let transition {
      let time = now
      progress = transition.sample(time)
      if time >= transition.started + transition.duration {
        finish()
        return
      }
      do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
    }
  }
}

private struct MorphingSurfaceLayout: Layout {
  let progress: Double
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
    let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
    let intrinsicHeight = sizes[0].height + (sizes[1].height - sizes[0].height) * progress
    return CGSize(
      width: width ?? sizes.map(\.width).max() ?? 0,
      height: proposal.height.flatMap { $0.isFinite ? max(0, $0) : nil } ?? intrinsicHeight)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let expandedOpacity = min(1, max(0, (progress - 0.2) / 0.5))
    for (index, child) in subviews.enumerated() {
      child.place(
        at: CGPoint(x: bounds.minX, y: bounds.minY + (index == 1 ? 8 * (1 - expandedOpacity) : 0)),
        anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
  }
}

struct NativeMorphingSurface: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  let node: RenderNodeState
  let properties: RenderMorphingSurface
  let controller: MorphingSurfaceController
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    let progress = controller.progress
    let corner = 16 * min(1, progress * 2)
    MorphingSurfaceLayout(progress: progress) {
      // EmptyView contributes no Layout subview; each branch needs a stable slot.
      ZStack(alignment: .topLeading) {
        NativeNodeView(node: node.children[0], activate: activate)
      }
      .opacity(max(0, 1 - progress / 0.35))
      .allowsHitTesting(!properties.expanded).disabled(properties.expanded)
      .accessibilityHidden(properties.expanded)
      ZStack(alignment: .topLeading) {
        NativeNodeView(node: node.children[1], activate: activate)
      }
      .opacity(min(1, max(0, (progress - 0.2) / 0.5)))
      .allowsHitTesting(properties.expanded).disabled(!properties.expanded)
      .accessibilityHidden(!properties.expanded)
    }
    .background(.background, in: RoundedRectangle(cornerRadius: corner))
    .clipShape(RoundedRectangle(cornerRadius: corner))
    .shadow(color: .black.opacity(0.15 * progress), radius: 3 * progress, y: progress)
    .padding(.horizontal, 8 * progress).padding(.vertical, 6 * progress)
    .onAppear {
      controller.setReducedMotion(reduceMotion)
      controller.setAnimationsActive(scenePhase == .active && node.progressAnimationsActive)
      controller.attach()
    }
    .onDisappear { controller.detach() }
    .onChange(of: reduceMotion) { _, value in controller.setReducedMotion(value) }
    .onChange(of: scenePhase) { _, value in
      controller.setAnimationsActive(value == .active && node.progressAnimationsActive)
    }
    .onChange(of: node.progressAnimationsActive) { _, value in
      controller.setAnimationsActive(value && scenePhase == .active)
    }
    .task(id: controller.animationID) { await controller.runAnimation(controller.animationID) }
  }
}
