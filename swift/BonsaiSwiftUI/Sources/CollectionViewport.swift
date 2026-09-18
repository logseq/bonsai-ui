import Observation
import SwiftUI

#if os(macOS)
  import AppKit
  typealias CollectionPlatformScrollView = NSScrollView
  typealias CollectionPlatformView = NSView
#else
  import UIKit
  typealias CollectionPlatformScrollView = UIScrollView
  typealias CollectionPlatformView = UIView
#endif

@MainActor @Observable final class CollectionViewport {
  private(set) var geometry: CollectionGeometry
  private(set) var overscan: Int
  private(set) var vertical: Bool
  @ObservationIgnored private var mounts: Set<UUID> = []
  var isMounted: Bool { !mounts.isEmpty }
  func attach(id: UUID) { mounts.insert(id) }
  func detach(id: UUID) {
    guard mounts.contains(id) else { return }
    if nativeAttachmentID == id || (nativeAttachmentID == nil && mounts.count == 1) {
      releaseNativeAttachment()
    }
    mounts.remove(id)
  }
  private(set) var animationID = 0
  @ObservationIgnored private var animation: CollectionAnimation?
  // Preserve a logical anchor across native pixel rounding; only actual user
  // scrolling changes it while an extent transition is running.
  @ObservationIgnored private var animationAnchor: CollectionAnchor?
  @ObservationIgnored private var measurementAnchor: CollectionAnchor?
  @ObservationIgnored private weak var nativeScroll: CollectionPlatformScrollView?
  @ObservationIgnored private weak var nativeContent: CollectionPlatformView?
  @ObservationIgnored private var nativeAttachmentID: UUID?
  @ObservationIgnored private var nativeVertical: Bool?
  func attachNative(
    _ scroll: CollectionPlatformScrollView, content: CollectionPlatformView, id: UUID,
    vertical: Bool, rightToLeft: Bool
  ) {
    guard vertical == self.vertical, rightToLeft == self.rightToLeft else { return }
    nativeScroll = scroll
    nativeContent = content
    nativeAttachmentID = id
    nativeVertical = vertical
  }
  func detachNative(id: UUID) {
    guard id == nativeAttachmentID else { return }
    releaseNativeAttachment()
  }
  func acceptsNativeObservation(id: UUID, vertical: Bool, rightToLeft: Bool) -> Bool {
    mounts.contains(id) && nativeAttachmentID == id
      && self.vertical == vertical && self.rightToLeft == rightToLeft
  }
  private func releaseNativeAttachment() {
    captureNativePosition()
    nativeScroll = nil
    nativeContent = nil
    nativeAttachmentID = nil
    nativeVertical = nil
    lastPhysicalOffset = nil
    finishAnimation()
    userIsScrolling = false
    position = vertical ? ScrollPosition(y: leadingOffset) : ScrollPosition(x: leadingOffset)
  }
  @ObservationIgnored private var lastPhysicalOffset: Double?
  private var nativeVisibleRect: CGRect? {
    guard nativeVertical == vertical, let nativeScroll else { return nil }
    #if os(macOS)
      return nativeScroll.contentView.bounds
    #else
      // Convert the actual native viewport into collection-content coordinates.
      // This includes content placement and safe-area/content insets without
      // assuming that UIScrollView.contentOffset starts at zero.
      guard let nativeContent else { return nil }
      return nativeContent.convert(nativeScroll.bounds, from: nativeScroll)
    #endif
  }
  private var nativePhysicalOffset: Double? {
    guard let rect = nativeVisibleRect else { return nil }
    return vertical ? rect.minY : rect.minX
  }
  private var nativeDocumentWidth: Double? {
    #if os(macOS)
      return nativeScroll?.documentView.map { Double($0.frame.width) }
    #else
      return nativeContent.map { Double($0.bounds.width) }
    #endif
  }
  private func scrollNative(to target: Double) {
    guard let nativeScroll else { return }
    #if os(macOS)
      var origin = nativeScroll.contentView.bounds.origin
      if vertical { origin.y = target } else { origin.x = target }
      nativeScroll.contentView.scroll(to: origin)
      nativeScroll.reflectScrolledClipView(nativeScroll.contentView)
    #else
      guard let actual = nativePhysicalOffset else { return }
      var offset = nativeScroll.contentOffset
      if vertical { offset.y += target - actual } else { offset.x += target - actual }
      nativeScroll.setContentOffset(offset, animated: false)
    #endif
  }
  private func captureNativePosition() {
    if animation != nil {
      adoptNativeTravel()
    } else if let physical = nativePhysicalOffset {
      let offset =
        !self.vertical && rightToLeft
        ? (nativeDocumentWidth ?? self.geometry.totalExtent)
          - (nativeVisibleRect.map { Double($0.width) } ?? visibleExtent) - physical
        : physical
      visibleRect.origin = self.vertical ? CGPoint(x: 0, y: offset) : CGPoint(x: offset, y: 0)
    }
  }
  private func adoptNativeTravel() {
    guard let actual = nativePhysicalOffset else { return }
    defer { lastPhysicalOffset = actual }
    guard let previous = lastPhysicalOffset, let animationAnchor else { return }
    let delta = (actual - previous) * (!vertical && rightToLeft ? -1 : 1)
    if delta != 0 {
      let offset = geometry.offset(for: animationAnchor, viewportExtent: visibleExtent)
      self.animationAnchor = geometry.anchor(at: offset + delta)
    }
  }
  @ObservationIgnored var userIsScrolling = false
  @ObservationIgnored var displayScale: Double = 1
  func setDirection(_ rightToLeft: Bool) {
    guard self.rightToLeft != rightToLeft else { return }
    releaseNativeAttachment()
    self.rightToLeft = rightToLeft
  }
  @ObservationIgnored var rightToLeft = false
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
  func prepareVisibleExtent(_ size: CGSize, vertical: Bool) {
    guard !isMounted, self.vertical == vertical, visibleExtent == 0,
      size.width.isFinite, size.height.isFinite, size.width >= 0, size.height >= 0
    else { return }
    visibleRect.size = size
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

  }
  func replace(
    _ geometry: CollectionGeometry, relocatedAnchorIndex: Int? = nil,
    relocatedAnchorOffset: Double? = nil, overscan: Int? = nil,
    timing: CollectionTiming = .immediate, vertical: Bool? = nil,
    preserveMeasurementAnchor: Bool = false, animatedIndices: Set<Int>? = nil
  ) {
    captureNativePosition()
    let sourceAnchor =
      measurementAnchor ?? animationAnchor ?? self.geometry.anchor(at: leadingOffset)
    let axisChanged = vertical.map { $0 != self.vertical } ?? false
    if let overscan, self.overscan != overscan { self.overscan = overscan }
    if !axisChanged, relocatedAnchorIndex == nil, relocatedAnchorOffset == nil,
      (animation?.target ?? self.geometry) == geometry
    {
      return
    }
    if let vertical { self.vertical = vertical }
    animation = nil
    animationAnchor = nil
    animationID += 1
    if !axisChanged, isMounted, animationsActive, !reducedMotion, relocatedAnchorIndex == nil,
      relocatedAnchorOffset == nil, timing != .immediate
    {
      let next = CollectionAnimation(
        from: self.geometry, to: geometry, timing: timing, started: now,
        animatedIndices: animatedIndices)
      let initial = next.sample(at: now)
      if !initial.finished {
        animation = next
        animationAnchor = sourceAnchor
        measurementAnchor = nil
        lastPhysicalOffset = nativePhysicalOffset
        if nativePhysicalOffset != nil { position.isPositionedByUser = true }
        return
      }
    }
    let correctedPosition = apply(
      geometry, relocatedAnchorIndex: relocatedAnchorIndex,
      relocatedAnchorOffset: relocatedAnchorOffset, sourceAnchor: sourceAnchor,
      forcePosition: axisChanged)
    // Only wait for native geometry when a position correction is outstanding.
    // An equal-position append or measurement must not mask the next scroll.
    if nativePhysicalOffset == nil, preserveMeasurementAnchor,
      correctedPosition || measurementAnchor != nil
    {
      measurementAnchor = geometry.anchor(at: leadingOffset)
    } else {
      measurementAnchor = nil
    }
  }
  @discardableResult private func apply(
    _ geometry: CollectionGeometry, relocatedAnchorIndex: Int? = nil,
    relocatedAnchorOffset: Double? = nil, sourceAnchor: CollectionAnchor? = nil,
    forcePosition: Bool = false
  ) -> Bool {
    if animation != nil { adoptNativeTravel() }
    let oldAnchor = sourceAnchor ?? animationAnchor ?? self.geometry.anchor(at: leadingOffset)
    let previousOffset =
      animationAnchor.map {
        self.geometry.offset(for: $0, viewportExtent: visibleExtent)
      } ?? leadingOffset
    if self.geometry != geometry { self.geometry = geometry }
    let offset: Double
    if let oldAnchor {
      let anchor = CollectionAnchor(
        index: relocatedAnchorIndex ?? oldAnchor.index,
        offset: relocatedAnchorOffset ?? oldAnchor.offset)
      offset = geometry.offset(for: anchor, viewportExtent: visibleExtent)
    } else {
      offset = 0
    }
    visibleRect.origin = vertical ? CGPoint(x: 0, y: offset) : CGPoint(x: offset, y: 0)
    // Compare the effective position in display pixels. Equal-position geometry
    // refinements must not reset ScrollPosition or interrupt a native gesture.
    let scale = displayScale.isFinite && displayScale > 0 ? displayScale : 1
    // RTL document growth changes the physical anchor even at the same logical offset.
    let effective = !vertical && rightToLeft ? geometry.totalExtent - offset : offset
    if let actual = nativePhysicalOffset {
      let rawTarget = !vertical && rightToLeft ? effective - visibleExtent : effective
      let target = (rawTarget * scale).rounded() / scale
      guard actual != target else { return false }
      if !storedPosition.isPositionedByUser { position.isPositionedByUser = true }
      scrollNative(to: target)
      lastPhysicalOffset = nativePhysicalOffset
    } else {
      guard forcePosition || (previousOffset * scale).rounded() != (offset * scale).rounded()
      else { return false }
      if vertical { position.scrollTo(y: offset) } else { position.scrollTo(x: offset) }
    }
    return true
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
  @Environment(\.layoutDirection) private var direction
  let viewport: CollectionViewport
  let firstIndex: Int
  var observation: ScrollObserver? = nil
  var command: NativeScrollCommand? = nil
  @ViewBuilder let content: () -> Content

  var body: some View {
    CollectionViewportContent(
      viewport: viewport, vertical: viewport.vertical, direction: direction, firstIndex: firstIndex,
      observation: observation,
      command: command, content: content
    )
    .id(
      CollectionViewportIdentity(
        viewport: ObjectIdentifier(viewport), vertical: viewport.vertical,
        rightToLeft: direction == .rightToLeft))
  }
}

private struct CollectionViewportContent<Content: View>: View {
  let viewport: CollectionViewport
  let vertical: Bool
  let direction: LayoutDirection
  let firstIndex: Int
  var observation: ScrollObserver? = nil
  var command: NativeScrollCommand? = nil
  @ViewBuilder let content: () -> Content

  @State private var attachmentID = UUID()

  var body: some View {
    @Bindable var viewport = viewport
    GeometryReader { container in
      ScrollView(vertical ? .vertical : .horizontal) {
        CollectionWindowLayout(
          geometry: viewport.geometry, firstIndex: firstIndex, vertical: vertical
        ) { content().environment(\.bonsaiRefresh, nil) }
        // Keep short and empty content in the viewport's coordinate space. A
        // zero-width RTL document gives ScrollPosition an invalid leading edge
        // when the catalog is populated again.
        .frame(
          minWidth: vertical ? nil : container.size.width,
          minHeight: vertical ? container.size.height : nil,
          alignment: .topLeading
        )
        .background(
          CollectionNativeScrollAccess(
            viewport: viewport, vertical: vertical, rightToLeft: direction == .rightToLeft,
            id: attachmentID))
      }
      .modifier(ScrollObservationModifier(observer: observation))
      .scrollPosition(
        Binding(
          get: { viewport.position },
          set: {
            if viewport.acceptsNativeObservation(
              id: attachmentID, vertical: vertical, rightToLeft: direction == .rightToLeft)
            {
              viewport.receiveNativePosition($0)
            }
          })
      )
      .modifier(NativeScrollCommandModifier(controller: command, position: $viewport.position))
      .modifier(
        CollectionViewportLifecycle(
          direction: direction, viewport: viewport, vertical: vertical, id: attachmentID))
    }
    .environment(\.layoutDirection, direction)
  }
}

private struct CollectionViewportIdentity: Hashable {
  let viewport: ObjectIdentifier
  let vertical: Bool
  let rightToLeft: Bool
}

private struct CollectionViewportLifecycle: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.displayScale) private var displayScale
  let direction: LayoutDirection
  let viewport: CollectionViewport
  let vertical: Bool
  let id: UUID

  func body(content: Content) -> some View {
    content
      .onScrollPhaseChange { _, phase in
        guard
          viewport.acceptsNativeObservation(
            id: id, vertical: vertical, rightToLeft: direction == .rightToLeft)
        else { return }
        viewport.userIsScrolling = phase == .interacting || phase == .decelerating
      }
      .onAppear {
        viewport.displayScale = displayScale
        viewport.setDirection(direction == .rightToLeft)
        viewport.setReducedMotion(reduceMotion)
        viewport.attach(id: id)
      }
      .onChange(of: displayScale) { _, value in viewport.displayScale = value }
      .onChange(of: reduceMotion) { _, value in viewport.setReducedMotion(value) }
      .task(id: viewport.animationID) { await viewport.runAnimation() }
      .onDisappear { viewport.detach(id: id) }
      .onScrollGeometryChange(for: CGRect.self) {
        $0.visibleRect
      } action: { _, rect in
        viewport.prepareVisibleExtent(rect.size, vertical: vertical)
        guard
          viewport.acceptsNativeObservation(
            id: id, vertical: vertical, rightToLeft: direction == .rightToLeft)
        else { return }
        viewport.observe(rect)
      }
  }
}

private struct CollectionNativeScrollAccess {
  let viewport: CollectionViewport
  let vertical: Bool
  let rightToLeft: Bool
  let id: UUID
}

#if os(macOS)
  extension CollectionNativeScrollAccess: NSViewRepresentable {
    func makeNSView(context: Context) -> CollectionNativeScrollAccessView {
      CollectionNativeScrollAccessView()
    }
    func updateNSView(_ view: CollectionNativeScrollAccessView, context: Context) {
      view.update(viewport: viewport, vertical: vertical, rightToLeft: rightToLeft, id: id)
    }
    static func dismantleNSView(_ view: CollectionNativeScrollAccessView, coordinator: ()) {
      view.retire()
    }
  }
#else
  extension CollectionNativeScrollAccess: UIViewRepresentable {
    func makeUIView(context: Context) -> CollectionNativeScrollAccessView {
      CollectionNativeScrollAccessView()
    }
    func updateUIView(_ view: CollectionNativeScrollAccessView, context: Context) {
      view.update(viewport: viewport, vertical: vertical, rightToLeft: rightToLeft, id: id)
    }
    static func dismantleUIView(_ view: CollectionNativeScrollAccessView, coordinator: ()) {
      view.retire()
    }
  }
#endif

@MainActor private final class CollectionNativeScrollAccessView: CollectionPlatformView {
  private var attachmentID = UUID()
  private var retired = false
  private weak var viewport: CollectionViewport?
  private var vertical = true
  private var rightToLeft = false

  func update(viewport: CollectionViewport, vertical: Bool, rightToLeft: Bool, id: UUID) {
    guard !retired else { return }
    if self.viewport !== viewport || self.vertical != vertical
      || self.rightToLeft != rightToLeft || attachmentID != id
    {
      detach()
    }
    self.viewport = viewport
    self.vertical = vertical
    self.rightToLeft = rightToLeft
    attachmentID = id
    attach()
  }
  func retire() {
    retired = true
    detach()
  }
  private func detach() { viewport?.detachNative(id: attachmentID) }
  private func attach() {
    guard !retired, window != nil else {
      detach()
      return
    }
    var parent = superview
    while let view = parent {
      if let scroll = view as? CollectionPlatformScrollView {
        viewport?.attachNative(
          scroll, content: self, id: attachmentID,
          vertical: vertical, rightToLeft: rightToLeft)
        return
      }
      parent = view.superview
    }
    detach()
  }

  // Read the last native position while both views still share a coordinate
  // hierarchy. In particular, UIKit conversion must precede window removal.
  #if os(macOS)
    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if window != nil, newWindow !== window { detach() }
      super.viewWillMove(toWindow: newWindow)
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
      if superview != nil, newSuperview !== superview { detach() }
      super.viewWillMove(toSuperview: newSuperview)
    }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      attach()
    }
    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      attach()
    }
  #else
    override func willMove(toWindow newWindow: UIWindow?) {
      if window != nil, newWindow !== window { detach() }
      super.willMove(toWindow: newWindow)
    }
    override func willMove(toSuperview newSuperview: UIView?) {
      if superview != nil, newSuperview !== superview { detach() }
      super.willMove(toSuperview: newSuperview)
    }
    override func didMoveToWindow() {
      super.didMoveToWindow()
      attach()
    }
    override func didMoveToSuperview() {
      super.didMoveToSuperview()
      attach()
    }
  #endif
}
