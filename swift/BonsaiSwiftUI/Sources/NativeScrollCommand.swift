import SwiftUI

@MainActor final class NativeScrollCommand {
  private var owner: UUID?
  private var position: Binding<ScrollPosition>?
  private var vertical: Bool
  private var visible = CGRect.zero
  private var content = CGSize.zero
  private var active = false
  private var disposed = false
  private var request: UUID?
  var reducedMotion = false

  init(vertical: Bool) { self.vertical = vertical }

  func attach(owner: UUID, position: Binding<ScrollPosition>) {
    guard !disposed else { return }
    if self.owner != owner { interrupt() }
    self.owner = owner
    self.position = position
  }
  func detach(owner: UUID) {
    guard self.owner == owner else { return }
    interrupt()
    self.owner = nil
    position = nil
    visible = .zero
    content = .zero
  }
  func synchronize(vertical: Bool) {
    guard self.vertical != vertical else { return }
    interrupt()
    self.vertical = vertical
    visible = .zero
    content = .zero
  }
  func setActive(_ value: Bool) {
    active = value
    if !value { interrupt() }
  }
  func observe(visible: CGRect, content: CGSize) {
    guard
      [visible.minX, visible.minY, visible.width, visible.height, content.width, content.height]
        .allSatisfy(\.isFinite)
    else { return }
    self.visible = visible
    self.content = content
  }
  func userInteraction() { interrupt() }
  private var offset: CGFloat { vertical ? visible.minY : visible.minX }
  private func move(_ offset: CGFloat) {
    guard var next = position?.wrappedValue else { return }
    if vertical { next.scrollTo(y: offset) } else { next.scrollTo(x: offset) }
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) { position?.wrappedValue = next }
  }
  private func interrupt() {
    guard request != nil else { return }
    request = nil
    move(offset)
  }
  func scroll(alignment: Double, animated: Bool) async throws {
    try Task.checkCancellation()
    let viewport = vertical ? visible.height : visible.width
    let extent = vertical ? content.height : content.width
    guard !disposed, active, owner != nil, position != nil, viewport > 0,
      alignment.isFinite
    else { throw HostServiceError.failed("Scroll target is not mounted and active") }
    interrupt()
    let target = max(0, extent - viewport) * min(1, max(0, alignment))
    if abs(offset - target) < 0.5 { return }
    let id = UUID()
    request = id
    defer { if request == id { request = nil } }
    let clock = ContinuousClock()
    let started = clock.now
    let initial = offset
    do {
      while true {
        try Task.checkCancellation()
        guard request == id, active, !disposed, owner != nil else { throw CancellationError() }
        let elapsed = started.duration(to: clock.now)
        let seconds =
          Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let fraction = animated && !reducedMotion ? min(1, seconds / 0.25) : 1
        let eased =
          fraction < 0.5
          ? 4 * fraction * fraction * fraction
          : 1 - pow(-2 * fraction + 2, 3) / 2
        move(initial + (target - initial) * eased)
        if fraction == 1, abs(offset - target) < 1 { return }
        guard elapsed < .seconds(2) else {
          throw HostServiceError.failed("The native scroll view did not reach the requested offset")
        }
        try await clock.sleep(for: .milliseconds(16))
      }
    } catch {
      if request == id { interrupt() }
      throw error
    }
  }
  func dispose() {
    interrupt()
    disposed = true
    active = false
    owner = nil
    position = nil
  }
}

private struct ScrollCommandGeometry: Equatable {
  let visible: CGRect
  let content: CGSize
}

struct NativeScrollCommandModifier: ViewModifier {
  let controller: NativeScrollCommand?
  @Binding var position: ScrollPosition
  @State private var owner = UUID()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .onAppear {
        controller?.reducedMotion = reduceMotion
        controller?.attach(owner: owner, position: $position)
      }
      .onDisappear { controller?.detach(owner: owner) }
      .onChange(of: reduceMotion) { _, value in controller?.reducedMotion = value }
      .onScrollGeometryChange(for: ScrollCommandGeometry.self) {
        ScrollCommandGeometry(visible: $0.visibleRect, content: $0.contentSize)
      } action: { _, next in
        controller?.observe(visible: next.visible, content: next.content)
      }
      .onScrollPhaseChange { _, phase in
        if phase == .interacting { controller?.userInteraction() }
      }
  }
}
