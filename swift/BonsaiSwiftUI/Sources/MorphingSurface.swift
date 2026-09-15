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
  private(set) var displayedExtent: Double?
  @ObservationIgnored private var targetExtent: Double?
  @ObservationIgnored private var extentTransition: Transition?
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
  func measureExtent(_ extent: Double, coordinated: Bool) {
    guard extent.isFinite, extent >= 0 else { return }
    if coordinated {
      targetExtent = nil
      displayedExtent = nil
      extentTransition = nil
      return
    }
    guard targetExtent != extent else { return }
    targetExtent = extent
    let duration =
      Double(
        properties.expanded
          ? properties.expandMilliseconds : properties.collapseMilliseconds) / 1000
    guard let from = displayedExtent, mounted > 0, active, !reducedMotion,
      duration > 0, !disposed
    else {
      displayedExtent = extent
      extentTransition = nil
      return
    }
    extentTransition = Transition(from: from, target: extent, started: now, duration: duration)
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
    if transition != nil || extentTransition != nil { animationID &+= 1 }
    transition = nil
    extentTransition = nil
    displayedExtent = targetExtent
    progress = properties.expanded ? 1 : 0
  }
  func runAnimation(_ id: UInt64) async {
    while !Task.isCancelled, !disposed, id == animationID {
      let time = now
      if let transition {
        progress = transition.sample(time)
        if time >= transition.started + transition.duration {
          progress = properties.expanded ? 1 : 0
          self.transition = nil
        }
      }
      if let extentTransition {
        displayedExtent = extentTransition.sample(time)
        if time >= extentTransition.started + extentTransition.duration {
          displayedExtent = targetExtent
          self.extentTransition = nil
        }
      }
      guard transition != nil || extentTransition != nil else { return }
      do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
    }
  }
}

private struct CollectionCoordinatesExtent: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var collectionCoordinatesExtent: Bool {
    get { self[CollectionCoordinatesExtent.self] }
    set { self[CollectionCoordinatesExtent.self] = newValue }
  }
}

struct NativeMorphingSurface: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.collectionCoordinatesExtent) private var coordinated
  let node: RenderNodeState
  let properties: RenderMorphingSurface
  let controller: MorphingSurfaceController
  let activate: @MainActor (RenderNodeState) -> Void

  private var styledContent: some View {
    let progress = controller.progress
    let corner = 16 * min(1, progress * 2)
    return ZStack(alignment: .topLeading) {
      NativeNodeView(node: node.children[0], activate: activate)
    }
    .background(.background, in: RoundedRectangle(cornerRadius: corner))
    .clipShape(RoundedRectangle(cornerRadius: corner))
    .shadow(color: .black.opacity(0.15 * progress), radius: 3 * progress, y: progress)
    .padding(.horizontal, properties.expanded ? 8 : 0)
    .padding(.vertical, properties.expanded ? 6 : 0)
    .fixedSize(horizontal: false, vertical: true)
  }

  var body: some View {
    styledContent
      .onGeometryChange(for: Double.self) { proxy in
        Double(proxy.size.height)
      } action: { extent in
        controller.measureExtent(extent, coordinated: coordinated)
      }
      .frame(
        height: coordinated ? nil : controller.displayedExtent.map { CGFloat($0) }, alignment: .top
      )
      .clipped()
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
