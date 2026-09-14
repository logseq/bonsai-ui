import Observation
import SwiftUI

@MainActor @Observable final class CollectionViewport {
  private(set) var geometry: CollectionGeometry
  private(set) var overscan: Int
  private(set) var vertical: Bool
  @ObservationIgnored private var mounts = 0
  var isMounted: Bool { mounts > 0 }
  func attach() { mounts += 1 }
  func detach() {
    mounts = max(0, mounts - 1)
    if !isMounted { finishAnimation() }
  }
  private(set) var animationID = 0
  @ObservationIgnored private var animation: CollectionAnimation?
  // Preserve a logical anchor across native pixel rounding; only actual user
  // scrolling changes it while an extent transition is running.
  @ObservationIgnored private var animationAnchor: CollectionAnchor?
  @ObservationIgnored private var measurementAnchor: CollectionAnchor?
  @ObservationIgnored var userIsScrolling = false
  @ObservationIgnored private var reducedMotion = false
  @ObservationIgnored private var animationsActive = true
  private var now: Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
  @ObservationIgnored private var storedPosition: ScrollPosition
  private var positionRevision: UInt64 = 0
  var position: ScrollPosition {
    get {
      _ = positionRevision
      return storedPosition
    }
    set {
      measurementAnchor = nil
      storedPosition = newValue
      positionRevision &+= 1
    }
  }
  func receiveNativePosition(_ value: ScrollPosition) {
    // Native writeback is an observation, not another programmatic scroll.
    // Publishing it invalidates the geometry being measured and can create
    // an endless layout/writeback cycle when measured content shrinks.
    storedPosition = value
  }
  @ObservationIgnored private(set) var visibleRect = CGRect.zero

  init(
    geometry: CollectionGeometry, vertical: Bool = true, overscan: Int = 4,
    initialOffset: Double = 0
  ) throws {
    guard overscan >= 0, overscan <= Int(UInt32.max), initialOffset.isFinite, initialOffset >= 0
    else { throw CollectionError.invalidWindow }
    self.geometry = geometry
    self.vertical = vertical
    storedPosition = vertical ? ScrollPosition(y: initialOffset) : ScrollPosition(x: initialOffset)
    visibleRect.origin =
      vertical ? CGPoint(x: 0, y: initialOffset) : CGPoint(x: initialOffset, y: 0)
    self.overscan = overscan
  }
  var leadingOffset: Double { vertical ? visibleRect.minY : visibleRect.minX }
  var visibleExtent: Double { vertical ? visibleRect.height : visibleRect.width }
  var visibleRange: Range<Int> {
    geometry.visibleRange(offset: leadingOffset, extent: visibleExtent)
  }
  var requestedWindow: Range<Int> {
    geometry.window(offset: leadingOffset, extent: visibleExtent, overscan: overscan)
  }
  func setAnimationsActive(_ value: Bool) {
    animationsActive = value
    if !value { finishAnimation() }
  }
  func setReducedMotion(_ value: Bool) {
    reducedMotion = value
    if value { finishAnimation() }
  }
  func finishAnimation() {
    guard let animation else { return }
    apply(animation.target)
    self.animation = nil
    animationAnchor = nil
    animationID += 1
  }
  func runAnimation() async {
    let identity = animationID
    while !Task.isCancelled, animationID == identity, let animation {
      let sample = animation.sample(at: now)
      apply(sample.geometry)
      if sample.finished {
        self.animation = nil
        animationAnchor = nil
        return
      }
      do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
    }
  }
  func observe(_ rect: CGRect) {
    guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
      rect.width >= 0, rect.height >= 0
    else { return }
    let previousExtent = visibleExtent
    let anchor = geometry.anchor(at: leadingOffset)
    if userIsScrolling { measurementAnchor = nil }
    if let measurementAnchor {
      let extent = vertical ? rect.height : rect.width
      let target = geometry.offset(for: measurementAnchor, viewportExtent: extent)
      let actual = vertical ? rect.minY : rect.minX
      // Geometry observations may still describe the previous layout while
      // measured rows refine its replacement. Wait for native point rounding
      // to reach the corrected position instead of interpreting that old point
      // against the new row sizes as a different logical anchor.
      if abs(actual - target) >= 1 {
        visibleRect.size = rect.size
        visibleRect.origin = vertical ? CGPoint(x: 0, y: target) : CGPoint(x: target, y: 0)
        return
      }
      self.measurementAnchor = nil
    }
    visibleRect = rect
    // Point-based ScrollPosition does not retain an exact offset on resize.
    // Preserve the leading logical item, including horizontal RTL containers.
    if previousExtent > 0, visibleExtent > 0, visibleExtent != previousExtent,
      !userIsScrolling
    {
      apply(geometry, sourceAnchor: anchor)
    }
    if animation != nil, userIsScrolling {
      animationAnchor = geometry.anchor(at: leadingOffset)
    }
  }
  func replace(
    _ geometry: CollectionGeometry, relocatedAnchorIndex: Int? = nil,
    relocatedAnchorOffset: Double? = nil, overscan: Int? = nil,
    timing: CollectionTiming = .immediate, vertical: Bool? = nil,
    preserveMeasurementAnchor: Bool = false
  ) {
    let sourceAnchor =
      measurementAnchor ?? animationAnchor ?? self.geometry.anchor(at: leadingOffset)
    let axisChanged = vertical.map { $0 != self.vertical } ?? false
    if let vertical { self.vertical = vertical }
    animation = nil
    animationAnchor = nil
    animationID += 1
    if let overscan { self.overscan = overscan }
    if !axisChanged, isMounted, animationsActive, !reducedMotion, relocatedAnchorIndex == nil,
      relocatedAnchorOffset == nil, timing != .immediate
    {
      let next = CollectionAnimation(
        from: self.geometry, to: geometry, timing: timing, started: now)
      let initial = next.sample(at: now)
      if !initial.finished {
        animation = next
        animationAnchor = sourceAnchor
        return
      }
    }
    apply(
      geometry, relocatedAnchorIndex: relocatedAnchorIndex,
      relocatedAnchorOffset: relocatedAnchorOffset, sourceAnchor: sourceAnchor)
    if preserveMeasurementAnchor {
      measurementAnchor = geometry.anchor(at: leadingOffset)
    } else {
      measurementAnchor = nil
    }
  }
  private func apply(
    _ geometry: CollectionGeometry, relocatedAnchorIndex: Int? = nil,
    relocatedAnchorOffset: Double? = nil, sourceAnchor: CollectionAnchor? = nil
  ) {
    let oldAnchor = sourceAnchor ?? animationAnchor ?? self.geometry.anchor(at: leadingOffset)
    self.geometry = geometry
    let offset: Double
    if let oldAnchor {
      let anchor = CollectionAnchor(
        index: relocatedAnchorIndex ?? oldAnchor.index,
        offset: relocatedAnchorOffset ?? oldAnchor.offset)
      offset = geometry.offset(for: anchor, viewportExtent: visibleExtent)
    } else {
      offset = 0
    }
    if vertical {
      visibleRect.origin = CGPoint(x: 0, y: offset)
      position.scrollTo(y: offset)
    } else {
      visibleRect.origin = CGPoint(x: offset, y: 0)
      position.scrollTo(x: offset)
    }
  }
}

private struct CollectionWindowLayout: Layout {
  let geometry: CollectionGeometry
  let firstIndex: Int
  let vertical: Bool

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    vertical
      ? CGSize(width: proposal.width ?? 0, height: geometry.totalExtent)
      : CGSize(width: geometry.totalExtent, height: proposal.height ?? 0)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    for (offset, subview) in subviews.enumerated() {
      let index = firstIndex + offset
      subview.place(
        at: vertical
          ? CGPoint(x: bounds.minX, y: bounds.minY + geometry.offset(at: index))
          : CGPoint(x: bounds.minX + geometry.offset(at: index), y: bounds.minY),
        anchor: .topLeading,
        proposal: vertical
          ? ProposedViewSize(width: bounds.width, height: geometry.extent(at: index))
          : ProposedViewSize(width: geometry.extent(at: index), height: bounds.height))
    }
  }
}

struct WindowedCollectionView<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let viewport: CollectionViewport
  let firstIndex: Int
  var observation: ScrollObserver? = nil
  var command: NativeScrollCommand? = nil
  @ViewBuilder let content: () -> Content

  var body: some View {
    @Bindable var viewport = viewport
    GeometryReader { container in
      ScrollView(viewport.vertical ? .vertical : .horizontal) {
        CollectionWindowLayout(
          geometry: viewport.geometry, firstIndex: firstIndex, vertical: viewport.vertical
        ) { content().environment(\.bonsaiRefresh, nil) }
        // Keep short and empty content in the viewport's coordinate space. A
        // zero-width RTL document gives ScrollPosition an invalid leading edge
        // when the catalog is populated again.
        .frame(
          minWidth: viewport.vertical ? nil : container.size.width,
          minHeight: viewport.vertical ? container.size.height : nil,
          alignment: .topLeading)
      }
      .modifier(RefreshScrollModifier())
      .modifier(SwipeScrollActivity())
      .modifier(ScrollObservationModifier(observer: observation))
      .scrollPosition(
        Binding(
          get: { viewport.position }, set: { viewport.receiveNativePosition($0) })
      )
      .modifier(NativeScrollCommandModifier(controller: command, position: $viewport.position))
      .onScrollPhaseChange { _, phase in
        viewport.userIsScrolling = phase == .interacting || phase == .decelerating
      }
      .onAppear {
        viewport.setReducedMotion(reduceMotion)
        viewport.attach()
      }
      .onChange(of: reduceMotion) { _, value in viewport.setReducedMotion(value) }
      .task(id: viewport.animationID) { await viewport.runAnimation() }
      .onDisappear { viewport.detach() }
      .onScrollGeometryChange(for: CGRect.self) {
        $0.visibleRect
      } action: { _, rect in
        viewport.observe(rect)
      }
    }
  }
}
